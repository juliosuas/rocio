import XCTest
import UIKit
@testable import Rocio

final class CloudFoundationTests: XCTestCase {
    func testCloudConfigurationFallbackUsesAnAvailableSystemSymbol() {
        XCTAssertNotNil(UIImage(systemName: "icloud.slash"))
    }

    func testLegacyGardenPlantDecodesWithMigrationTimestamp() throws {
        let id = UUID()
        let addedAt = Date(timeIntervalSinceReferenceDate: 1234)
        let legacy = LegacyGardenPlant(
            id: id,
            flowerId: "rosa",
            nickname: "Rose",
            addedAt: addedAt,
            lastWateredAt: addedAt,
            status: .healthy,
            notes: ""
        )

        let decoded = try JSONDecoder().decode(GardenPlant.self, from: JSONEncoder().encode(legacy))

        XCTAssertEqual(decoded.id, id)
        XCTAssertEqual(decoded.updatedAt, addedAt)
    }

    func testGardenUpsertPayloadNormalizesLegacyTextWithoutSplittingComposedEmoji() {
        let composedEmoji = "👨‍👩‍👧‍👦"
        let nicknamePrefix = String(repeating: "n", count: 79)
        let notesPrefix = String(repeating: "x", count: 1_999)
        let legacyPlant = GardenPlant(
            flowerId: "rosa",
            nickname: nicknamePrefix + composedEmoji,
            notes: notesPrefix + composedEmoji
        )

        let gardenEpoch = UUID()
        let payload = GardenPlantUpsertPayload(
            plant: legacyPlant,
            userID: UUID(),
            gardenEpoch: gardenEpoch
        )

        XCTAssertEqual(payload.nickname, nicknamePrefix)
        XCTAssertEqual(payload.nickname.unicodeScalars.count, 79)
        XCTAssertEqual(payload.notes, notesPrefix)
        XCTAssertEqual(payload.notes.unicodeScalars.count, 1_999)
        XCTAssertEqual(payload.gardenEpoch, gardenEpoch)
        XCTAssertEqual(legacyPlant.nickname, nicknamePrefix + composedEmoji)
        XCTAssertEqual(legacyPlant.notes, notesPrefix + composedEmoji)
    }

    func testGardenDeletionPayloadUsesSupabaseTombstoneColumns() throws {
        let deletedAt = Date(timeIntervalSince1970: 1_800_000_100)
        let payload = GardenDeletionPayload(deletedAt: deletedAt, updatedAt: deletedAt)
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(payload)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])

        XCTAssertEqual(Set(json.keys), ["deleted_at", "updated_at"])
        XCTAssertEqual(json["deleted_at"], json["updated_at"])
    }

    func testCloudGardenRecordDecodesSupabaseDeletedAt() throws {
        let id = UUID()
        let json = """
        {
          "id": "\(id.uuidString.lowercased())",
          "flower_id": "deleted",
          "nickname": "Deleted plant",
          "added_at": "2026-07-21T12:34:56Z",
          "last_watered_at": "2026-07-21T12:34:56Z",
          "status": "healthy",
          "notes": "",
          "updated_at": "2026-07-21T12:34:56Z",
          "deleted_at": "2026-07-21T12:34:56Z"
        }
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601

        let record = try decoder.decode(CloudGardenRecord.self, from: Data(json.utf8))

        XCTAssertEqual(record.id, id)
        XCTAssertNotNil(record.deletedAt)
    }

    func testCloudGardenSyncStateDecodesServerEpochAndResetTimestamp() throws {
        let epoch = UUID()
        let json = """
        [{
          "garden_epoch": "\(epoch.uuidString.lowercased())",
          "garden_reset_at": "2026-07-21T12:34:56Z"
        }]
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601

        let state = try XCTUnwrap(
            decoder.decode([CloudGardenSyncState].self, from: Data(json.utf8)).first
        )

        XCTAssertEqual(state.gardenEpoch, epoch)
        XCTAssertNotNil(state.gardenResetAt)
    }

    func testLegacyPendingDeleteWithoutTimestampStillDecodes() throws {
        let changeID = UUID()
        let plantID = UUID()
        let data = try JSONSerialization.data(withJSONObject: [
            "id": changeID.uuidString,
            "kind": "delete",
            "plantID": plantID.uuidString,
        ])

        let change = try JSONDecoder().decode(PendingCloudChange.self, from: data)

        XCTAssertEqual(change.id, changeID)
        XCTAssertEqual(change.kind, .delete)
        XCTAssertEqual(change.plantID, plantID)
        XCTAssertNil(change.occurredAt)
    }

    func testPendingGardenDeletionRetainsItsOriginalTimestamp() {
        let plantID = UUID()
        let occurredAt = Date(timeIntervalSince1970: 1_800_000_200)

        let change = PendingCloudChange(.delete(plantID, at: occurredAt))

        XCTAssertEqual(change.kind, .delete)
        XCTAssertEqual(change.plantID, plantID)
        XCTAssertEqual(change.occurredAt, occurredAt)
    }

    func testBackendSendsGardenDeletionPatchAndResetRPC() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BackendURLProtocolStub.self]
        let urlSession = URLSession(configuration: configuration)
        defer {
            urlSession.invalidateAndCancel()
            BackendURLProtocolStub.handler = nil
        }

        let recorder = BackendRequestRecorder()
        let resetEpoch = UUID()
        BackendURLProtocolStub.handler = { request in
            recorder.append(request)
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: request.url?.path == "/rest/v1/rpc/reset_my_garden" ? 200 : 204,
                httpVersion: nil,
                headerFields: nil
            )!
            let data = request.url?.path == "/rest/v1/rpc/reset_my_garden"
                ? try JSONEncoder().encode(resetEpoch)
                : Data()
            return (response, data)
        }

        let client = RocioBackendClient(
            configuration: BackendConfiguration(
                baseURL: URL(string: "https://example.supabase.co")!,
                anonymousKey: "public-anon-key"
            ),
            urlSession: urlSession
        )
        let plantID = UUID()
        let resetRequestID = UUID()
        let deletedAt = Date(timeIntervalSince1970: 1_800_000_300)
        let session = AuthSession(
            accessToken: "access-token",
            refreshToken: "refresh-token",
            expiresAt: .distantFuture,
            user: AuthUser(id: UUID(), email: "gardener@example.com")
        )

        try await client.deletePlant(id: plantID, deletedAt: deletedAt, session: session)
        let returnedEpoch = try await client.resetGarden(requestID: resetRequestID, session: session)

        let captured = recorder.requests
        XCTAssertEqual(captured.count, 2)
        XCTAssertEqual(captured[0].httpMethod, "PATCH")
        XCTAssertEqual(captured[0].url?.path, "/rest/v1/garden_plants")
        XCTAssertEqual(captured[0].url?.query, "id=eq.\(plantID.uuidString.lowercased())")
        XCTAssertEqual(captured[0].value(forHTTPHeaderField: "Authorization"), "Bearer access-token")
        XCTAssertEqual(captured[1].httpMethod, "POST")
        XCTAssertEqual(captured[1].url?.path, "/rest/v1/rpc/reset_my_garden")
        XCTAssertEqual(captured[1].value(forHTTPHeaderField: "Authorization"), "Bearer access-token")
        XCTAssertEqual(returnedEpoch, resetEpoch)
    }

    func testBackendConfigurationStoresPublicEndpointAndKey() {
        let url = URL(string: "https://example.supabase.co")!
        let configuration = BackendConfiguration(baseURL: url, anonymousKey: "public-anon-key")

        XCTAssertEqual(configuration.baseURL, url)
        XCTAssertEqual(configuration.anonymousKey, "public-anon-key")
    }

    func testIdentificationProviderLabelsFallbackHonestly() {
        XCTAssertEqual(
            IdentificationProvider.onDeviceFallback.label,
            L10n.text("scanner.provider.fallback", fallback: "On-device fallback")
        )
    }

    func testBackendErrorsNeverExposeRawServerMessages() {
        let error = BackendError.server(code: "unexpected_provider_error", message: "sensitive upstream detail")

        XCTAssertEqual(
            error.errorDescription,
            L10n.text("error.cloud.generic", fallback: "Rocio Cloud is temporarily unavailable. Try again.")
        )
        XCTAssertFalse(error.errorDescription?.contains("sensitive") ?? true)
    }

    func testKnownAuthErrorUsesLocalizedMessage() {
        let error = BackendError.server(code: "invalid_credentials", message: "Invalid login credentials")

        XCTAssertEqual(
            error.errorDescription,
            L10n.text("error.auth.invalid", fallback: "The email or password is incorrect.")
        )
    }

    func testCancelledGardenSyncGenerationCannotFinishAReplacementTask() {
        var generations = GardenSyncTaskGeneration()
        let cancelled = generations.begin()

        generations.cancel()
        let replacement = generations.begin()

        XCTAssertFalse(generations.finish(cancelled))
        XCTAssertEqual(generations.current, replacement)
        XCTAssertTrue(generations.finish(replacement))
        XCTAssertNil(generations.current)
    }

    func testGardenSyncGenerationFinishesOnlyOnce() {
        var generations = GardenSyncTaskGeneration()
        let active = generations.begin()

        XCTAssertTrue(generations.finish(active))
        XCTAssertFalse(generations.finish(active))
    }

    func testRemoteTombstoneWinsOverANewerStaleLocalPlant() {
        let id = UUID()
        let remotePlant = GardenPlant(
            id: id,
            flowerId: "rosa",
            nickname: "Deleted rose",
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let staleLocalPlant = GardenPlant(
            id: id,
            flowerId: "rosa",
            nickname: "Offline edit after deletion",
            updatedAt: Date(timeIntervalSince1970: 300)
        )
        let tombstone = CloudGardenRecord(
            plant: remotePlant,
            deletedAt: Date(timeIntervalSince1970: 200)
        )

        let resolved = GardenSyncResolver.resolve(
            local: [staleLocalPlant],
            remote: [tombstone]
        )

        XCTAssertTrue(resolved.isEmpty)
    }

    func testResetTombstoneRemovesAStaleCopyFromAnotherDevice() {
        let id = UUID()
        let staleDeviceCopy = GardenPlant(
            id: id,
            flowerId: "orquidea",
            nickname: "Office orchid",
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let resetTombstone = CloudGardenRecord(
            plant: staleDeviceCopy,
            deletedAt: Date(timeIntervalSince1970: 200)
        )

        let resolved = GardenSyncResolver.resolve(
            local: [staleDeviceCopy],
            remote: [resetTombstone]
        )

        XCTAssertTrue(resolved.isEmpty)
    }

    func testAuthoritativeFetchRemovesAnOfflineOnlyPlantRejectedByResetEpoch() {
        let offlineOnlyPlant = GardenPlant(
            flowerId: "girasol",
            nickname: "Offline sunflower",
            updatedAt: Date(timeIntervalSince1970: 100)
        )

        let attemptedUpload = GardenSyncResolver.resolve(
            local: [offlineOnlyPlant],
            remote: []
        )
        XCTAssertEqual(attemptedUpload, [offlineOnlyPlant])

        let serverTombstone = CloudGardenRecord(
            plant: offlineOnlyPlant,
            deletedAt: Date(timeIntervalSince1970: 200)
        )
        let authoritative = GardenSyncResolver.reconcileAuthoritative(
            baseline: [offlineOnlyPlant],
            current: [offlineOnlyPlant],
            remote: [serverTombstone]
        )

        XCTAssertTrue(authoritative.isEmpty)
    }

    func testAuthoritativeReconciliationPreservesOnlyChangesMadeDuringSync() {
        let unchangedRejectedPlant = GardenPlant(
            flowerId: "rosa",
            nickname: "Rejected stale rose",
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let addedDuringSync = GardenPlant(
            flowerId: "lavanda",
            nickname: "New lavender",
            updatedAt: Date(timeIntervalSince1970: 300)
        )

        let reconciled = GardenSyncResolver.reconcileAuthoritative(
            baseline: [unchangedRejectedPlant],
            current: [unchangedRejectedPlant, addedDuringSync],
            remote: []
        )

        XCTAssertEqual(reconciled, [addedDuringSync])
    }

    func testAuthoritativeReconciliationPreservesADeletionMadeDuringSync() {
        let deletedDuringSync = GardenPlant(
            flowerId: "orquidea",
            nickname: "Deleted while syncing",
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let staleRemote = CloudGardenRecord(plant: deletedDuringSync, deletedAt: nil)

        let reconciled = GardenSyncResolver.reconcileAuthoritative(
            baseline: [deletedDuringSync],
            current: [],
            remote: [staleRemote]
        )

        XCTAssertTrue(reconciled.isEmpty)
    }

    @MainActor
    func testOfflineRefreshFailurePreservesPersistedGardenAndSession() async {
        let plant = GardenPlant(flowerId: "rosa", nickname: "Offline rose")
        let savedSession = expiredSession()
        var didClearSession = false
        GardenPersistence.savePlants([plant])
        defer { GardenPersistence.clearPlants() }
        let gardenStore = GardenStore()
        let sessionStore = SessionStore(
            configuration: testBackendConfiguration,
            sessionPersistence: SessionPersistence(
                load: { savedSession },
                save: { _ in XCTFail("An offline refresh must not replace the saved session") },
                clear: { didClearSession = true }
            ),
            refreshSession: { _ in throw URLError(.notConnectedToInternet) }
        )

        await sessionStore.bootstrap(gardenStore: gardenStore)

        XCTAssertEqual(sessionStore.state, .signedIn(savedSession))
        XCTAssertEqual(
            sessionStore.syncMessage,
            L10n.text("cloud.pending", fallback: "Saved on this device; cloud sync pending")
        )
        XCTAssertFalse(didClearSession)
        XCTAssertEqual(gardenStore.plants, [plant])
        XCTAssertEqual(GardenPersistence.loadPlants(), [plant])
    }

    @MainActor
    func testAmbiguousUnauthorizedRefreshPreservesGardenAndSession() async {
        let plant = GardenPlant(flowerId: "rosa", nickname: "Unauthorized rose")
        let savedSession = expiredSession()
        var didClearSession = false
        let gardenStore = GardenStore(plants: [plant])
        let sessionStore = SessionStore(
            configuration: testBackendConfiguration,
            sessionPersistence: SessionPersistence(
                load: { savedSession },
                save: { _ in XCTFail("An ambiguous refresh failure must not replace the saved session") },
                clear: { didClearSession = true }
            ),
            refreshSession: { _ in
                throw BackendError.server(code: "http_401", message: "Unauthorized")
            }
        )

        await sessionStore.bootstrap(gardenStore: gardenStore)

        XCTAssertEqual(sessionStore.state, .signedIn(savedSession))
        XCTAssertEqual(
            sessionStore.syncMessage,
            L10n.text("cloud.pending", fallback: "Saved on this device; cloud sync pending")
        )
        XCTAssertFalse(didClearSession)
        XCTAssertEqual(gardenStore.plants, [plant])
    }

    @MainActor
    func testRevokedRefreshTokenClearsSessionAndGarden() async {
        let plant = GardenPlant(flowerId: "rosa", nickname: "Revoked rose")
        let savedSession = expiredSession()
        var didClearSession = false
        let gardenStore = GardenStore(plants: [plant])
        let sessionStore = SessionStore(
            configuration: testBackendConfiguration,
            sessionPersistence: SessionPersistence(
                load: { savedSession },
                save: { _ in XCTFail("A revoked session must not be saved") },
                clear: { didClearSession = true }
            ),
            refreshSession: { _ in
                throw BackendError.server(code: "refresh_token_not_found", message: "Refresh token not found")
            }
        )

        await sessionStore.bootstrap(gardenStore: gardenStore)

        XCTAssertEqual(sessionStore.state, .signedOut)
        XCTAssertTrue(didClearSession)
        XCTAssertTrue(gardenStore.plants.isEmpty)
    }

    @MainActor
    func testValidationFailedPreservesPersistedGardenAndSession() async {
        let plant = GardenPlant(flowerId: "rosa", nickname: "Validation rose")
        let savedSession = expiredSession()
        var didClearSession = false
        GardenPersistence.savePlants([plant])
        defer { GardenPersistence.clearPlants() }
        let gardenStore = GardenStore()
        let sessionStore = SessionStore(
            configuration: testBackendConfiguration,
            sessionPersistence: SessionPersistence(
                load: { savedSession },
                save: { _ in XCTFail("A validation failure must not replace the saved session") },
                clear: { didClearSession = true }
            ),
            refreshSession: { _ in
                throw BackendError.server(code: "validation_failed", message: "Parameters are invalid")
            }
        )

        await sessionStore.bootstrap(gardenStore: gardenStore)

        XCTAssertEqual(sessionStore.state, .signedIn(savedSession))
        XCTAssertEqual(
            sessionStore.syncMessage,
            L10n.text("cloud.pending", fallback: "Saved on this device; cloud sync pending")
        )
        XCTAssertFalse(didClearSession)
        XCTAssertEqual(gardenStore.plants, [plant])
        XCTAssertEqual(GardenPersistence.loadPlants(), [plant])
    }

    @MainActor
    func testExplicitSupabaseSessionInvalidationCodesClearSessionAndGarden() async {
        for code in ["session_expired", "user_banned"] {
            let plant = GardenPlant(flowerId: "rosa", nickname: "Invalid session rose")
            let savedSession = expiredSession()
            var didClearSession = false
            let gardenStore = GardenStore(plants: [plant])
            let sessionStore = SessionStore(
                configuration: testBackendConfiguration,
                sessionPersistence: SessionPersistence(
                    load: { savedSession },
                    save: { _ in XCTFail("An explicitly invalid session must not be saved: \(code)") },
                    clear: { didClearSession = true }
                ),
                refreshSession: { _ in
                    throw BackendError.server(code: code, message: "Session invalid")
                }
            )

            await sessionStore.bootstrap(gardenStore: gardenStore)

            XCTAssertEqual(sessionStore.state, .signedOut, "code: \(code)")
            XCTAssertTrue(didClearSession, "code: \(code)")
            XCTAssertTrue(gardenStore.plants.isEmpty, "code: \(code)")
        }
    }

#if DEBUG
    @MainActor
    func testDebugDemoDoesNotCreateAnAuthenticatedSession() {
        let gardenStore = GardenStore(plants: [])
        let sessionStore = SessionStore(configuration: nil)

        sessionStore.enterDemo(gardenStore: gardenStore)

        XCTAssertEqual(sessionStore.state, .demo)
        XCTAssertTrue(sessionStore.isDemoMode)
        XCTAssertNil(sessionStore.session)

        sessionStore.exitDemo(gardenStore: gardenStore)

        XCTAssertEqual(sessionStore.state, .unconfigured)
        XCTAssertFalse(gardenStore.isDemoMode)
    }
#endif

    private var testBackendConfiguration: BackendConfiguration {
        BackendConfiguration(baseURL: URL(string: "https://example.supabase.co")!, anonymousKey: "public-anon-key")
    }

    private func expiredSession() -> AuthSession {
        AuthSession(
            accessToken: "expired-access-token",
            refreshToken: "refresh-token",
            expiresAt: Date(timeIntervalSinceNow: -60),
            user: AuthUser(id: UUID(), email: "gardener@example.com")
        )
    }
}
private struct LegacyGardenPlant: Codable {
    let id: UUID
    let flowerId: String
    let nickname: String
    let addedAt: Date
    let lastWateredAt: Date
    let status: PlantStatus
    let notes: String
}

private final class BackendURLProtocolStub: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            guard let handler = Self.handler else {
                throw URLError(.badServerResponse)
            }
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private final class BackendRequestRecorder {
    private let lock = NSLock()
    private var recorded: [URLRequest] = []

    var requests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func append(_ request: URLRequest) {
        lock.lock()
        defer { lock.unlock() }
        recorded.append(request)
    }
}
