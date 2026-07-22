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

    func testBackendSignOutOnlyRevokesTheCurrentDeviceSession() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BackendURLProtocolStub.self]
        let urlSession = URLSession(configuration: configuration)
        defer {
            urlSession.invalidateAndCancel()
            BackendURLProtocolStub.handler = nil
        }
        let recorder = BackendRequestRecorder()
        BackendURLProtocolStub.handler = { request in
            recorder.append(request)
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 204,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }
        let client = RocioBackendClient(
            configuration: testBackendConfiguration,
            urlSession: urlSession
        )
        let session = validSession(userID: UUID())

        await client.signOut(session: session)

        let request = try XCTUnwrap(recorder.requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/auth/v1/logout")
        XCTAssertEqual(request.url?.query, "scope=local")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer valid-access-token")
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
    func testSuccessfulNoOpUpsertReadsBackTombstoneAndRemovesLocalPlant() async throws {
        let userID = UUID()
        let epoch = UUID()
        let plant = GardenPlant(
            flowerId: "rosa",
            nickname: "Offline rose",
            updatedAt: Date(timeIntervalSince1970: 1_800_000_100)
        )
        clearGardenSyncTestState(userID: userID)
        let scenario = GardenSyncBackendScenario(plant: plant, gardenEpoch: epoch)
        let urlSession = makeStubbedURLSession(handler: scenario.response)
        let gardenStore = GardenStore(plants: [plant])
        let session = validSession(userID: userID)
        let sessionStore = SessionStore(
            configuration: testBackendConfiguration,
            sessionPersistence: SessionPersistence(
                load: { session },
                save: { _ in },
                clear: {}
            ),
            refreshSession: { $0 },
            urlSession: urlSession
        )
        defer {
            gardenStore.cloudChangeHandler = nil
            BackendURLProtocolStub.handler = nil
            urlSession.invalidateAndCancel()
            clearGardenSyncTestState(userID: userID)
        }

        await sessionStore.bootstrap(gardenStore: gardenStore)
        XCTAssertEqual(gardenStore.plants.map(\.id), [plant.id])
        let requestCountBeforeMutation = scenario.signatures.count
        scenario.setTombstoned()
        gardenStore.cloudChangeHandler = { [weak gardenStore, weak sessionStore] change in
            guard let gardenStore, let sessionStore else { return }
            sessionStore.enqueueGardenChange(change, gardenStore: gardenStore)
        }

        gardenStore.update(
            plant,
            nickname: "Edit after remote delete",
            status: .healthy,
            notes: "Should be removed by authoritative readback"
        )
        await sessionStore.waitForGardenSync()

        let mutationRequests = Array(scenario.signatures.dropFirst(requestCountBeforeMutation))
        let upsertIndex = try XCTUnwrap(
            mutationRequests.firstIndex(of: "POST /rest/v1/garden_plants")
        )
        XCTAssertTrue(
            mutationRequests.dropFirst(upsertIndex + 1).contains("GET /rest/v1/garden_plants"),
            "A successful upsert must be followed by an authoritative garden readback"
        )
        XCTAssertTrue(gardenStore.plants.isEmpty)
        XCTAssertTrue(GardenPersistence.loadPlants().isEmpty)
        XCTAssertNil(UserDefaults.standard.data(forKey: pendingGardenKey(userID)))
        XCTAssertEqual(sessionStore.syncMessage, L10n.text("cloud.synced", fallback: "Synced"))
    }

    @MainActor
    func testForegroundRefreshPullsRemoteTombstoneWithoutLocalMutation() async {
        let userID = UUID()
        let plant = GardenPlant(
            flowerId: "orquidea",
            nickname: "Office orchid",
            updatedAt: Date(timeIntervalSince1970: 1_800_000_100)
        )
        clearGardenSyncTestState(userID: userID)
        let scenario = GardenSyncBackendScenario(plant: plant, gardenEpoch: UUID())
        let urlSession = makeStubbedURLSession(handler: scenario.response)
        let gardenStore = GardenStore(plants: [plant])
        let session = validSession(userID: userID)
        let sessionStore = SessionStore(
            configuration: testBackendConfiguration,
            sessionPersistence: SessionPersistence(
                load: { session },
                save: { _ in },
                clear: {}
            ),
            refreshSession: { $0 },
            urlSession: urlSession
        )
        defer {
            BackendURLProtocolStub.handler = nil
            urlSession.invalidateAndCancel()
            clearGardenSyncTestState(userID: userID)
        }

        await sessionStore.bootstrap(gardenStore: gardenStore)
        XCTAssertEqual(gardenStore.plants.map(\.id), [plant.id])
        scenario.setTombstoned()

        await sessionStore.refreshGarden(gardenStore: gardenStore)

        XCTAssertTrue(gardenStore.plants.isEmpty)
        XCTAssertTrue(GardenPersistence.loadPlants().isEmpty)
        XCTAssertEqual(sessionStore.syncMessage, L10n.text("cloud.synced", fallback: "Synced"))
    }

    @MainActor
    func testSignOutCancelsBootstrapSyncBeforeItCanUploadCapturedGarden() async {
        let userID = UUID()
        let plant = GardenPlant(
            flowerId: "rosa",
            nickname: "Local rose",
            updatedAt: Date(timeIntervalSince1970: 1_800_000_100)
        )
        clearGardenSyncTestState(userID: userID)
        let scenario = BlockingGardenFetchScenario(plant: plant, gardenEpoch: UUID())
        let urlSession = makeStubbedURLSession(handler: scenario.response)
        let gardenStore = GardenStore(plants: [plant])
        let session = validSession(userID: userID)
        let sessionStore = SessionStore(
            configuration: testBackendConfiguration,
            sessionPersistence: SessionPersistence(
                load: { session },
                save: { _ in },
                clear: {}
            ),
            refreshSession: { $0 },
            urlSession: urlSession
        )
        defer {
            scenario.releaseGardenFetch()
            BackendURLProtocolStub.handler = nil
            urlSession.invalidateAndCancel()
            clearGardenSyncTestState(userID: userID)
        }

        let bootstrapTask = Task { await sessionStore.bootstrap(gardenStore: gardenStore) }
        await scenario.waitUntilGardenFetchIsBlocked()
        let signOutTask = Task { await sessionStore.signOut(gardenStore: gardenStore) }
        await scenario.waitUntil { sessionStore.state == .signedOut }
        scenario.releaseGardenFetch()

        await signOutTask.value
        await bootstrapTask.value

        XCTAssertEqual(sessionStore.state, .signedOut)
        XCTAssertNil(sessionStore.session)
        XCTAssertTrue(gardenStore.plants.isEmpty)
        XCTAssertFalse(scenario.signatures.contains("POST /rest/v1/garden_plants"))
    }

    @MainActor
    func testSignOutDuringBootstrapRefreshCannotRestoreClearedCredentials() async {
        let savedSession = expiredSession()
        let refreshedSession = AuthSession(
            accessToken: "refreshed-access-token",
            refreshToken: "refreshed-refresh-token",
            expiresAt: .distantFuture,
            user: savedSession.user
        )
        let refresher = BlockingSessionRefresher()
        let scenario = AuthLifecycleRaceScenario(
            userID: savedSession.user.id,
            gardenEpoch: UUID(),
            gardenResetAt: nil
        )
        let urlSession = makeStubbedURLSession(handler: scenario.response)
        let gardenStore = GardenStore(plants: [])
        var savedAfterClear: [AuthSession] = []
        var didClear = false
        let sessionStore = SessionStore(
            configuration: testBackendConfiguration,
            sessionPersistence: SessionPersistence(
                load: { savedSession },
                save: { session in savedAfterClear.append(session) },
                clear: { didClear = true }
            ),
            refreshSession: { session in try await refresher.refresh(session) },
            urlSession: urlSession
        )
        defer {
            BackendURLProtocolStub.handler = nil
            urlSession.invalidateAndCancel()
            clearGardenSyncTestState(userID: savedSession.user.id)
        }

        let bootstrapTask = Task { await sessionStore.bootstrap(gardenStore: gardenStore) }
        await refresher.waitUntilStarted()
        await sessionStore.signOut(gardenStore: gardenStore)
        await refresher.release(returning: refreshedSession)
        await bootstrapTask.value

        XCTAssertTrue(didClear)
        XCTAssertTrue(savedAfterClear.isEmpty)
        XCTAssertEqual(sessionStore.state, .signedOut)
        XCTAssertNil(sessionStore.session)
    }

    @MainActor
    func testBootstrapPublishesSavedSessionBeforeGardenHandshakeCompletes() async {
        let userID = UUID()
        let serverEpoch = UUID()
        let savedSession = validSession(userID: userID)
        let scenario = AuthLifecycleRaceScenario(
            userID: userID,
            gardenEpoch: serverEpoch,
            gardenResetAt: "2026-07-21T10:00:00Z"
        )
        scenario.blockNextProfileFetch()
        let urlSession = makeStubbedURLSession(handler: scenario.response)
        let gardenStore = GardenStore(plants: [])
        let sessionStore = SessionStore(
            configuration: testBackendConfiguration,
            sessionPersistence: SessionPersistence(
                load: { savedSession },
                save: { _ in },
                clear: {}
            ),
            refreshSession: { $0 },
            urlSession: urlSession
        )
        clearGardenSyncTestState(userID: userID)
        defer {
            scenario.releaseProfileFetch()
            BackendURLProtocolStub.handler = nil
            urlSession.invalidateAndCancel()
            clearGardenSyncTestState(userID: userID)
        }

        let bootstrapTask = Task { await sessionStore.bootstrap(gardenStore: gardenStore) }
        await scenario.waitUntilProfileFetchIsBlocked()

        XCTAssertEqual(sessionStore.state, .signedIn(savedSession))
        XCTAssertFalse(sessionStore.isGardenCloudReady)

        scenario.releaseProfileFetch()
        await bootstrapTask.value

        XCTAssertTrue(sessionStore.isGardenCloudReady)
        XCTAssertEqual(
            UserDefaults.standard.string(
                forKey: "rocio.cloud.garden-epoch.authoritative.\(userID.uuidString.lowercased())"
            ),
            serverEpoch.uuidString.lowercased()
        )
    }

    @MainActor
    func testSignInPublishesSessionBeforeHandshakeAndQuarantinesPreflightWrite() async throws {
        let userID = UUID()
        let serverEpoch = UUID()
        let scenario = AuthLifecycleRaceScenario(
            userID: userID,
            gardenEpoch: serverEpoch,
            gardenResetAt: "2026-07-21T10:00:00Z"
        )
        scenario.blockNextProfileFetch()
        let urlSession = makeStubbedURLSession(handler: scenario.response)
        let gardenStore = GardenStore(plants: [])
        let sessionStore = SessionStore(
            configuration: testBackendConfiguration,
            sessionPersistence: SessionPersistence(
                load: { nil },
                save: { _ in },
                clear: {}
            ),
            refreshSession: { $0 },
            urlSession: urlSession
        )
        clearGardenSyncTestState(userID: userID)
        gardenStore.cloudChangeHandler = { [weak gardenStore, weak sessionStore] change in
            guard let gardenStore, let sessionStore else { return }
            sessionStore.enqueueGardenChange(change, gardenStore: gardenStore)
        }
        defer {
            scenario.releaseProfileFetch()
            gardenStore.cloudChangeHandler = nil
            BackendURLProtocolStub.handler = nil
            urlSession.invalidateAndCancel()
            clearGardenSyncTestState(userID: userID)
        }

        await sessionStore.bootstrap(gardenStore: gardenStore)
        XCTAssertEqual(sessionStore.state, .signedOut)

        let signInTask = Task {
            await sessionStore.signIn(
                email: "gardener@example.com",
                password: "password123",
                gardenStore: gardenStore
            )
        }
        await scenario.waitUntilProfileFetchIsBlocked()

        XCTAssertEqual(sessionStore.session?.user.id, userID)
        XCTAssertFalse(sessionStore.isGardenCloudReady)
        let rose = try XCTUnwrap(FlowerCatalog.flower(id: "rosa"))
        gardenStore.add(rose)
        XCTAssertEqual(scenario.gardenPostCount, 0)
        XCTAssertNotNil(UserDefaults.standard.data(forKey: pendingGardenKey(userID)))

        scenario.releaseProfileFetch()
        await signInTask.value

        XCTAssertEqual(sessionStore.session?.user.id, userID)
        XCTAssertTrue(sessionStore.isGardenCloudReady)
        XCTAssertEqual(
            UserDefaults.standard.string(
                forKey: "rocio.cloud.garden-epoch.authoritative.\(userID.uuidString.lowercased())"
            ),
            serverEpoch.uuidString.lowercased()
        )
        XCTAssertEqual(scenario.gardenPostCount, 0)
        let quarantinedData = try XCTUnwrap(
            UserDefaults.standard.data(forKey: pendingGardenKey(userID))
        )
        let quarantinedPending = try JSONDecoder().decode([PendingCloudChange].self, from: quarantinedData)
        XCTAssertEqual(quarantinedPending.count, 1)
        XCTAssertNil(quarantinedPending[0].gardenEpoch)
        XCTAssertEqual(gardenStore.plants.map(\.flowerId), ["rosa"])

        // A deliberate edit after the epoch snapshot replaces the ambiguous
        // preflight-era intent and is safe to stamp and upload.
        let localRose = try XCTUnwrap(gardenStore.plants.first)
        gardenStore.water(localRose, at: Date(timeIntervalSince1970: 1_750_000_000))
        await sessionStore.waitForGardenSync()

        XCTAssertGreaterThanOrEqual(scenario.gardenPostCount, 1)
        XCTAssertFalse(scenario.postedGardenEpochs.isEmpty)
        XCTAssertTrue(scenario.postedGardenEpochs.allSatisfy { $0 == serverEpoch })
        XCTAssertEqual(gardenStore.plants.map(\.flowerId), ["rosa"])
        XCTAssertNil(UserDefaults.standard.data(forKey: pendingGardenKey(userID)))
    }

    @MainActor
    func testFailedInitialGardenHandshakePreservesAuthAndPendingWithoutPosting() async throws {
        let userID = UUID()
        let staleEpoch = UUID()
        let scenario = AuthLifecycleRaceScenario(
            userID: userID,
            gardenEpoch: UUID(),
            gardenResetAt: "2026-07-21T10:00:00Z",
            failsProfileFetch: true
        )
        let urlSession = makeStubbedURLSession(handler: scenario.response)
        let gardenStore = GardenStore(plants: [])
        var saveCount = 0
        var didClear = false
        let sessionStore = SessionStore(
            configuration: testBackendConfiguration,
            sessionPersistence: SessionPersistence(
                load: { nil },
                save: { _ in saveCount += 1 },
                clear: { didClear = true }
            ),
            refreshSession: { $0 },
            urlSession: urlSession
        )
        clearGardenSyncTestState(userID: userID)
        UserDefaults.standard.set(
            staleEpoch.uuidString.lowercased(),
            forKey: "rocio.cloud.garden-epoch.authoritative.\(userID.uuidString.lowercased())"
        )
        gardenStore.cloudChangeHandler = { [weak gardenStore, weak sessionStore] change in
            guard let gardenStore, let sessionStore else { return }
            sessionStore.enqueueGardenChange(change, gardenStore: gardenStore)
        }
        defer {
            gardenStore.cloudChangeHandler = nil
            BackendURLProtocolStub.handler = nil
            urlSession.invalidateAndCancel()
            clearGardenSyncTestState(userID: userID)
        }

        await sessionStore.bootstrap(gardenStore: gardenStore)
        await sessionStore.signIn(
            email: "gardener@example.com",
            password: "password123",
            gardenStore: gardenStore
        )
        let rose = try XCTUnwrap(FlowerCatalog.flower(id: "rosa"))
        let profileFetchCountBeforeEdit = scenario.profileFetchCount
        gardenStore.add(rose)
        await sessionStore.waitForGardenSync()

        XCTAssertEqual(saveCount, 1)
        XCTAssertFalse(didClear)
        XCTAssertEqual(sessionStore.session?.user.id, userID)
        XCTAssertFalse(sessionStore.isGardenCloudReady)
        XCTAssertEqual(
            UserDefaults.standard.string(
                forKey: "rocio.cloud.garden-epoch.authoritative.\(userID.uuidString.lowercased())"
            ),
            staleEpoch.uuidString.lowercased()
        )
        XCTAssertEqual(scenario.gardenPostCount, 0)
        XCTAssertGreaterThan(scenario.profileFetchCount, profileFetchCountBeforeEdit)
        XCTAssertEqual(gardenStore.plants.map(\.flowerId), ["rosa"])
        XCTAssertEqual(GardenPersistence.loadPlants().map(\.flowerId), ["rosa"])
        XCTAssertNotNil(UserDefaults.standard.data(forKey: pendingGardenKey(userID)))
        XCTAssertEqual(
            sessionStore.syncMessage,
            L10n.text("cloud.pending", fallback: "Saved on this device; cloud sync pending")
        )
        XCTAssertNil(sessionStore.errorMessage)
    }

    @MainActor
    func testQueuedEditRetriesRecoveredHandshakeWithoutSceneTransition() async throws {
        let userID = UUID()
        let serverEpoch = UUID()
        let scenario = AuthLifecycleRaceScenario(
            userID: userID,
            gardenEpoch: serverEpoch,
            gardenResetAt: "2026-07-21T10:00:00Z",
            failsProfileFetch: true
        )
        let urlSession = makeStubbedURLSession(handler: scenario.response)
        let gardenStore = GardenStore(plants: [])
        let sessionStore = SessionStore(
            configuration: testBackendConfiguration,
            sessionPersistence: SessionPersistence(
                load: { nil },
                save: { _ in },
                clear: {}
            ),
            refreshSession: { $0 },
            urlSession: urlSession
        )
        clearGardenSyncTestState(userID: userID)
        gardenStore.cloudChangeHandler = { [weak gardenStore, weak sessionStore] change in
            guard let gardenStore, let sessionStore else { return }
            sessionStore.enqueueGardenChange(change, gardenStore: gardenStore)
        }
        defer {
            gardenStore.cloudChangeHandler = nil
            BackendURLProtocolStub.handler = nil
            urlSession.invalidateAndCancel()
            clearGardenSyncTestState(userID: userID)
        }

        await sessionStore.bootstrap(gardenStore: gardenStore)
        await sessionStore.signIn(
            email: "gardener@example.com",
            password: "password123",
            gardenStore: gardenStore
        )
        XCTAssertFalse(sessionStore.isGardenCloudReady)
        let failedProfileFetchCount = scenario.profileFetchCount
        scenario.setFailsProfileFetch(false)

        let rose = try XCTUnwrap(FlowerCatalog.flower(id: "rosa"))
        gardenStore.add(rose)
        await sessionStore.waitForGardenSync()

        XCTAssertGreaterThan(scenario.profileFetchCount, failedProfileFetchCount)
        XCTAssertTrue(sessionStore.isGardenCloudReady)
        XCTAssertEqual(scenario.gardenPostCount, 0)
        XCTAssertNotNil(UserDefaults.standard.data(forKey: pendingGardenKey(userID)))

        let localRose = try XCTUnwrap(gardenStore.plants.first)
        gardenStore.water(localRose, at: Date(timeIntervalSince1970: 1_750_000_000))
        await sessionStore.waitForGardenSync()

        XCTAssertGreaterThanOrEqual(scenario.gardenPostCount, 1)
        XCTAssertTrue(scenario.postedGardenEpochs.allSatisfy { $0 == serverEpoch })
        XCTAssertEqual(gardenStore.plants.map(\.flowerId), ["rosa"])
        XCTAssertNil(UserDefaults.standard.data(forKey: pendingGardenKey(userID)))
    }

    @MainActor
    func testResetEpochMismatchPreservesInheritedPendingWithoutPosting() async throws {
        let userID = UUID()
        let staleEpoch = UUID()
        let serverEpoch = UUID()
        let plant = GardenPlant(flowerId: "rosa", nickname: "Inherited offline rose")
        let session = validSession(userID: userID)
        let scenario = AuthLifecycleRaceScenario(
            userID: userID,
            gardenEpoch: serverEpoch,
            gardenResetAt: "2026-07-21T10:00:00Z"
        )
        let urlSession = makeStubbedURLSession(handler: scenario.response)
        let gardenStore = GardenStore(plants: [plant])
        let sessionStore = SessionStore(
            configuration: testBackendConfiguration,
            sessionPersistence: SessionPersistence(
                load: { session },
                save: { _ in },
                clear: {}
            ),
            refreshSession: { $0 },
            urlSession: urlSession
        )
        clearGardenSyncTestState(userID: userID)
        GardenPersistence.savePlants([plant])
        UserDefaults.standard.set(
            staleEpoch.uuidString.lowercased(),
            forKey: "rocio.cloud.garden-epoch.authoritative.\(userID.uuidString.lowercased())"
        )
        let pending = PendingCloudChange(.upsert(plant))
        UserDefaults.standard.set(
            try JSONEncoder().encode([pending]),
            forKey: pendingGardenKey(userID)
        )
        defer {
            BackendURLProtocolStub.handler = nil
            urlSession.invalidateAndCancel()
            clearGardenSyncTestState(userID: userID)
        }

        await sessionStore.bootstrap(gardenStore: gardenStore)

        XCTAssertEqual(sessionStore.session?.user.id, userID)
        XCTAssertTrue(sessionStore.isGardenCloudReady)
        XCTAssertGreaterThan(scenario.profileFetchCount, 0)
        XCTAssertEqual(scenario.gardenPostCount, 0)
        XCTAssertEqual(gardenStore.plants, [plant])
        XCTAssertEqual(GardenPersistence.loadPlants(), [plant])
        let savedPendingData = try XCTUnwrap(
            UserDefaults.standard.data(forKey: pendingGardenKey(userID))
        )
        XCTAssertEqual(try JSONDecoder().decode([PendingCloudChange].self, from: savedPendingData).map(\.id), [pending.id])
    }

    @MainActor
    func testCurrentEditSyncsWhileInheritedEpochConflictStaysQuarantined() async throws {
        let userID = UUID()
        let staleEpoch = UUID()
        let serverEpoch = UUID()
        let inheritedPlant = GardenPlant(flowerId: "rosa", nickname: "Inherited rose")
        let inheritedChange = PendingCloudChange(.upsert(inheritedPlant))
        let session = validSession(userID: userID)
        let scenario = AuthLifecycleRaceScenario(
            userID: userID,
            gardenEpoch: serverEpoch,
            gardenResetAt: "2026-07-21T10:00:00Z"
        )
        let urlSession = makeStubbedURLSession(handler: scenario.response)
        let gardenStore = GardenStore(plants: [inheritedPlant])
        let sessionStore = SessionStore(
            configuration: testBackendConfiguration,
            sessionPersistence: SessionPersistence(
                load: { session },
                save: { _ in },
                clear: {}
            ),
            refreshSession: { $0 },
            urlSession: urlSession
        )
        clearGardenSyncTestState(userID: userID)
        GardenPersistence.savePlants([inheritedPlant])
        UserDefaults.standard.set(
            staleEpoch.uuidString.lowercased(),
            forKey: "rocio.cloud.garden-epoch.authoritative.\(userID.uuidString.lowercased())"
        )
        UserDefaults.standard.set(
            try JSONEncoder().encode([inheritedChange]),
            forKey: pendingGardenKey(userID)
        )
        gardenStore.cloudChangeHandler = { [weak gardenStore, weak sessionStore] change in
            guard let gardenStore, let sessionStore else { return }
            sessionStore.enqueueGardenChange(change, gardenStore: gardenStore)
        }
        defer {
            gardenStore.cloudChangeHandler = nil
            BackendURLProtocolStub.handler = nil
            urlSession.invalidateAndCancel()
            clearGardenSyncTestState(userID: userID)
        }

        await sessionStore.bootstrap(gardenStore: gardenStore)
        let orchid = try XCTUnwrap(FlowerCatalog.flower(id: "orquidea"))
        gardenStore.add(orchid)
        let orchidPlantID = try XCTUnwrap(
            gardenStore.plants.first(where: { $0.flowerId == orchid.id })?.id
        )
        await sessionStore.waitForGardenSync()

        XCTAssertTrue(sessionStore.isGardenCloudReady)
        XCTAssertGreaterThanOrEqual(scenario.gardenPostCount, 1)
        XCTAssertTrue(scenario.postedGardenEpochs.allSatisfy { $0 == serverEpoch })
        XCTAssertEqual(Set(scenario.postedGardenPlantIDs), Set([orchidPlantID]))
        XCTAssertFalse(scenario.postedGardenPlantIDs.contains(inheritedPlant.id))
        XCTAssertEqual(Set(gardenStore.plants.map(\.flowerId)), Set(["rosa", "orquidea"]))
        let savedPendingData = try XCTUnwrap(
            UserDefaults.standard.data(forKey: pendingGardenKey(userID))
        )
        let remaining = try JSONDecoder().decode([PendingCloudChange].self, from: savedPendingData)
        XCTAssertEqual(remaining.map(\.id), [inheritedChange.id])
        XCTAssertNil(remaining[0].gardenEpoch)
        XCTAssertNil(remaining[0].lifecycleID)
    }

    @MainActor
    func testPendingStampedWithServerEpochResumesAfterRelaunch() async throws {
        let userID = UUID()
        let serverEpoch = UUID()
        let timestamp = Date(timeIntervalSince1970: 1_750_000_000)
        let plant = GardenPlant(
            flowerId: "rosa",
            nickname: "Stamped offline rose",
            addedAt: timestamp,
            lastWateredAt: timestamp,
            updatedAt: timestamp
        )
        let pending = PendingCloudChange(.upsert(plant))
        let session = validSession(userID: userID)
        let scenario = AuthLifecycleRaceScenario(
            userID: userID,
            gardenEpoch: serverEpoch,
            gardenResetAt: nil,
            failsGardenPost: true
        )
        let urlSession = makeStubbedURLSession(handler: scenario.response)
        let firstGardenStore = GardenStore(plants: [plant])
        var firstSessionStore: SessionStore? = SessionStore(
            configuration: testBackendConfiguration,
            sessionPersistence: SessionPersistence(
                load: { session },
                save: { _ in },
                clear: {}
            ),
            refreshSession: { $0 },
            urlSession: urlSession
        )
        clearGardenSyncTestState(userID: userID)
        UserDefaults.standard.set(
            try JSONEncoder().encode([pending]),
            forKey: pendingGardenKey(userID)
        )
        defer {
            scenario.releaseProfileFetch()
            BackendURLProtocolStub.handler = nil
            urlSession.invalidateAndCancel()
            clearGardenSyncTestState(userID: userID)
        }

        await firstSessionStore?.bootstrap(gardenStore: firstGardenStore)

        XCTAssertFalse(try XCTUnwrap(firstSessionStore).isGardenCloudReady)
        XCTAssertEqual(scenario.gardenPostCount, 1)
        let stampedData = try XCTUnwrap(
            UserDefaults.standard.data(forKey: pendingGardenKey(userID))
        )
        let stampedPending = try JSONDecoder().decode([PendingCloudChange].self, from: stampedData)
        XCTAssertEqual(stampedPending.map(\.id), [pending.id])
        XCTAssertEqual(stampedPending[0].gardenEpoch, serverEpoch)
        XCTAssertNil(stampedPending[0].lifecycleID)

        // Simulate process teardown: this store has a new lifecycle and can
        // resume only from provenance persisted by the first preflight.
        firstSessionStore = nil
        scenario.setFailsGardenPost(false)
        scenario.blockNextProfileFetch()
        let relaunchedGardenStore = GardenStore(plants: [plant])
        let relaunchedSessionStore = SessionStore(
            configuration: testBackendConfiguration,
            sessionPersistence: SessionPersistence(
                load: { session },
                save: { _ in },
                clear: {}
            ),
            refreshSession: { $0 },
            urlSession: urlSession
        )

        let relaunchBootstrapTask = Task {
            await relaunchedSessionStore.bootstrap(gardenStore: relaunchedGardenStore)
        }
        await scenario.waitUntilProfileFetchIsBlocked()
        XCTAssertEqual(scenario.gardenPostCount, 1)
        scenario.releaseProfileFetch()
        await relaunchBootstrapTask.value

        XCTAssertTrue(relaunchedSessionStore.isGardenCloudReady)
        XCTAssertGreaterThanOrEqual(scenario.gardenPostCount, 2)
        XCTAssertTrue(scenario.postedGardenEpochs.allSatisfy { $0 == serverEpoch })
        XCTAssertEqual(relaunchedGardenStore.plants, [plant])
        XCTAssertNil(UserDefaults.standard.data(forKey: pendingGardenKey(userID)))
    }

    @MainActor
    func testUserResetResolvesInheritedPendingEpochConflict() async throws {
        let userID = UUID()
        let staleEpoch = UUID()
        let serverEpoch = UUID()
        let resetEpoch = UUID()
        let plant = GardenPlant(flowerId: "rosa", nickname: "Conflicted offline rose")
        let session = validSession(userID: userID)
        let scenario = AuthLifecycleRaceScenario(
            userID: userID,
            gardenEpoch: serverEpoch,
            gardenResetAt: "2026-07-21T10:00:00Z",
            resetEpoch: resetEpoch
        )
        let urlSession = makeStubbedURLSession(handler: scenario.response)
        let gardenStore = GardenStore(plants: [plant])
        let sessionStore = SessionStore(
            configuration: testBackendConfiguration,
            sessionPersistence: SessionPersistence(
                load: { session },
                save: { _ in },
                clear: {}
            ),
            refreshSession: { $0 },
            urlSession: urlSession
        )
        clearGardenSyncTestState(userID: userID)
        GardenPersistence.savePlants([plant])
        UserDefaults.standard.set(
            staleEpoch.uuidString.lowercased(),
            forKey: "rocio.cloud.garden-epoch.authoritative.\(userID.uuidString.lowercased())"
        )
        UserDefaults.standard.set(
            try JSONEncoder().encode([PendingCloudChange(.upsert(plant))]),
            forKey: pendingGardenKey(userID)
        )
        gardenStore.cloudChangeHandler = { [weak gardenStore, weak sessionStore] change in
            guard let gardenStore, let sessionStore else { return }
            sessionStore.enqueueGardenChange(change, gardenStore: gardenStore)
        }
        defer {
            gardenStore.cloudChangeHandler = nil
            BackendURLProtocolStub.handler = nil
            urlSession.invalidateAndCancel()
            clearGardenSyncTestState(userID: userID)
        }

        await sessionStore.bootstrap(gardenStore: gardenStore)
        XCTAssertTrue(sessionStore.isGardenCloudReady)
        XCTAssertNotNil(UserDefaults.standard.data(forKey: pendingGardenKey(userID)))

        gardenStore.reset()
        await sessionStore.waitForGardenSync()

        XCTAssertTrue(sessionStore.isGardenCloudReady)
        XCTAssertEqual(scenario.gardenResetCount, 1)
        XCTAssertEqual(scenario.gardenPostCount, 0)
        XCTAssertTrue(gardenStore.plants.isEmpty)
        XCTAssertNil(UserDefaults.standard.data(forKey: pendingGardenKey(userID)))
        XCTAssertEqual(
            UserDefaults.standard.string(
                forKey: "rocio.cloud.garden-epoch.authoritative.\(userID.uuidString.lowercased())"
            ),
            resetEpoch.uuidString.lowercased()
        )
    }

    @MainActor
    func testPlantAddedWhileResetRPCIsInFlightUsesReturnedEpoch() async throws {
        let userID = UUID()
        let serverEpoch = UUID()
        let resetEpoch = UUID()
        let session = validSession(userID: userID)
        let scenario = AuthLifecycleRaceScenario(
            userID: userID,
            gardenEpoch: serverEpoch,
            gardenResetAt: nil,
            resetEpoch: resetEpoch
        )
        let urlSession = makeStubbedURLSession(handler: scenario.response)
        let gardenStore = GardenStore(plants: [])
        let sessionStore = SessionStore(
            configuration: testBackendConfiguration,
            sessionPersistence: SessionPersistence(
                load: { session },
                save: { _ in },
                clear: {}
            ),
            refreshSession: { $0 },
            urlSession: urlSession
        )
        clearGardenSyncTestState(userID: userID)
        gardenStore.cloudChangeHandler = { [weak gardenStore, weak sessionStore] change in
            guard let gardenStore, let sessionStore else { return }
            sessionStore.enqueueGardenChange(change, gardenStore: gardenStore)
        }
        defer {
            scenario.releaseGardenResetRequest()
            gardenStore.cloudChangeHandler = nil
            BackendURLProtocolStub.handler = nil
            urlSession.invalidateAndCancel()
            clearGardenSyncTestState(userID: userID)
        }

        await sessionStore.bootstrap(gardenStore: gardenStore)
        XCTAssertTrue(sessionStore.isGardenCloudReady)

        scenario.blockNextGardenReset()
        gardenStore.reset()
        await scenario.waitUntilGardenResetRequestIsBlocked()

        let orchid = try XCTUnwrap(FlowerCatalog.flower(id: "orquidea"))
        gardenStore.add(orchid)
        scenario.releaseGardenResetRequest()
        await sessionStore.waitForGardenSync()

        XCTAssertEqual(scenario.gardenResetCount, 1)
        XCTAssertGreaterThanOrEqual(scenario.gardenPostCount, 1)
        XCTAssertTrue(scenario.postedGardenEpochs.allSatisfy { $0 == resetEpoch })
        XCTAssertEqual(gardenStore.plants.map(\.flowerId), ["orquidea"])
        XCTAssertNil(UserDefaults.standard.data(forKey: pendingGardenKey(userID)))
        XCTAssertEqual(
            UserDefaults.standard.string(
                forKey: "rocio.cloud.garden-epoch.authoritative.\(userID.uuidString.lowercased())"
            ),
            resetEpoch.uuidString.lowercased()
        )
    }

    @MainActor
    func testResetEpochMismatchWithoutPendingAdoptsRemoteSnapshot() async {
        let userID = UUID()
        let staleEpoch = UUID()
        let serverEpoch = UUID()
        let plant = GardenPlant(flowerId: "rosa", nickname: "Stale cached rose")
        let session = validSession(userID: userID)
        let scenario = AuthLifecycleRaceScenario(
            userID: userID,
            gardenEpoch: serverEpoch,
            gardenResetAt: "2026-07-21T10:00:00Z"
        )
        let urlSession = makeStubbedURLSession(handler: scenario.response)
        let gardenStore = GardenStore(plants: [plant])
        let sessionStore = SessionStore(
            configuration: testBackendConfiguration,
            sessionPersistence: SessionPersistence(
                load: { session },
                save: { _ in },
                clear: {}
            ),
            refreshSession: { $0 },
            urlSession: urlSession
        )
        clearGardenSyncTestState(userID: userID)
        UserDefaults.standard.set(
            staleEpoch.uuidString.lowercased(),
            forKey: "rocio.cloud.garden-epoch.authoritative.\(userID.uuidString.lowercased())"
        )
        defer {
            BackendURLProtocolStub.handler = nil
            urlSession.invalidateAndCancel()
            clearGardenSyncTestState(userID: userID)
        }

        await sessionStore.bootstrap(gardenStore: gardenStore)

        XCTAssertTrue(sessionStore.isGardenCloudReady)
        XCTAssertEqual(scenario.gardenPostCount, 0)
        XCTAssertTrue(gardenStore.plants.isEmpty)
        XCTAssertEqual(
            UserDefaults.standard.string(
                forKey: "rocio.cloud.garden-epoch.authoritative.\(userID.uuidString.lowercased())"
            ),
            serverEpoch.uuidString.lowercased()
        )
    }

    @MainActor
    func testSignInStartedDuringSignOutWaitsThenPerformsGardenHandshake() async {
        let oldUserID = UUID()
        let newUserID = UUID()
        let oldSession = validSession(userID: oldUserID)
        let scenario = AuthLifecycleRaceScenario(
            userID: newUserID,
            gardenEpoch: UUID(),
            gardenResetAt: nil
        )
        let urlSession = makeStubbedURLSession(handler: scenario.response)
        let gardenStore = GardenStore(plants: [])
        let sessionStore = SessionStore(
            configuration: testBackendConfiguration,
            sessionPersistence: SessionPersistence(
                load: { oldSession },
                save: { _ in },
                clear: {}
            ),
            refreshSession: { $0 },
            urlSession: urlSession
        )
        clearGardenSyncTestState(userID: oldUserID)
        clearGardenSyncTestState(userID: newUserID)
        defer {
            scenario.releaseLogoutRequest()
            BackendURLProtocolStub.handler = nil
            urlSession.invalidateAndCancel()
            clearGardenSyncTestState(userID: oldUserID)
            clearGardenSyncTestState(userID: newUserID)
        }

        await sessionStore.bootstrap(gardenStore: gardenStore)
        XCTAssertEqual(sessionStore.session?.user.id, oldUserID)
        let profileFetchCountBeforeLogin = scenario.profileFetchCount
        scenario.blockNextLogoutRequest()

        let signOutTask = Task { await sessionStore.signOut(gardenStore: gardenStore) }
        await scenario.waitUntilLogoutRequestIsBlocked()
        XCTAssertEqual(sessionStore.state, .signedOut)
        XCTAssertNil(sessionStore.session)
        let signInAttemptStarted = expectation(description: "The second sign-in task started")
        let signInTask = Task {
            signInAttemptStarted.fulfill()
            await sessionStore.signIn(
                email: "gardener@example.com",
                password: "password123",
                gardenStore: gardenStore
            )
        }
        await fulfillment(of: [signInAttemptStarted], timeout: 1)

        XCTAssertEqual(
            scenario.authRequestCount,
            0,
            "A new login must wait until the previous logout finishes"
        )
        scenario.releaseLogoutRequest()
        await signOutTask.value
        await signInTask.value

        XCTAssertEqual(sessionStore.session?.user.id, newUserID)
        XCTAssertGreaterThan(
            scenario.profileFetchCount,
            profileFetchCountBeforeLogin,
            "The login that resumes after sign-out must perform its garden epoch handshake"
        )
    }

    func testLogWateringIntentAdvancesConflictTimestampWithWateringDate() async throws {
        let oldDate = Date(timeIntervalSince1970: 1_700_000_000)
        let plant = GardenPlant(
            flowerId: "rosa",
            nickname: "Siri rose",
            lastWateredAt: oldDate,
            status: .needsWater,
            updatedAt: oldDate
        )
        GardenPersistence.savePlants([plant])
        defer { GardenPersistence.clearPlants() }
        let intent = LogWateringIntent()
        intent.plant = GardenPlantEntity(
            id: plant.id.uuidString,
            name: plant.nickname,
            flowerName: "Rose"
        )

        _ = try await intent.perform()

        let watered = try XCTUnwrap(GardenPersistence.loadPlants().first)
        XCTAssertEqual(watered.lastWateredAt, watered.updatedAt)
        XCTAssertGreaterThan(watered.updatedAt, oldDate)
        XCTAssertEqual(watered.status, .healthy)
        let staleRemote = CloudGardenRecord(
            plant: GardenPlant(
                id: plant.id,
                flowerId: plant.flowerId,
                nickname: plant.nickname,
                addedAt: plant.addedAt,
                lastWateredAt: oldDate,
                status: .needsWater,
                notes: plant.notes,
                updatedAt: oldDate.addingTimeInterval(1)
            ),
            deletedAt: nil
        )
        XCTAssertEqual(GardenSyncResolver.resolve(local: [watered], remote: [staleRemote]), [watered])
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

    private func makeStubbedURLSession(
        handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BackendURLProtocolStub.self]
        BackendURLProtocolStub.handler = handler
        return URLSession(configuration: configuration)
    }

    private func validSession(userID: UUID) -> AuthSession {
        AuthSession(
            accessToken: "valid-access-token",
            refreshToken: "valid-refresh-token",
            expiresAt: .distantFuture,
            user: AuthUser(id: userID, email: "gardener@example.com")
        )
    }

    private func pendingGardenKey(_ userID: UUID) -> String {
        "rocio.cloud.pending.\(userID.uuidString.lowercased())"
    }

    private func clearGardenSyncTestState(userID: UUID) {
        GardenPersistence.clearPlants()
        let suffix = userID.uuidString.lowercased()
        UserDefaults.standard.removeObject(forKey: "rocio.cloud.pending.\(suffix)")
        UserDefaults.standard.removeObject(forKey: "rocio.cloud.garden-epoch.authoritative.\(suffix)")
        UserDefaults.standard.removeObject(forKey: "rocio.cloud.garden-epoch.provisional.\(suffix)")
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

private final class GardenSyncBackendScenario: @unchecked Sendable {
    private let lock = NSLock()
    private let plant: GardenPlant
    private let gardenEpoch: UUID
    private var isTombstoned = false
    private var recordedSignatures: [String] = []

    init(plant: GardenPlant, gardenEpoch: UUID) {
        self.plant = plant
        self.gardenEpoch = gardenEpoch
    }

    var signatures: [String] {
        lock.lock()
        defer { lock.unlock() }
        return recordedSignatures
    }

    func setTombstoned() {
        lock.lock()
        isTombstoned = true
        lock.unlock()
    }

    func response(for request: URLRequest) throws -> (HTTPURLResponse, Data) {
        guard let url = request.url else { throw URLError(.badURL) }
        lock.lock()
        recordedSignatures.append("\(request.httpMethod ?? "GET") \(url.path)")
        let tombstoned = isTombstoned
        lock.unlock()

        let status: Int
        let data: Data
        switch (request.httpMethod, url.path) {
        case ("GET", "/rest/v1/profiles"):
            status = 200
            data = try JSONSerialization.data(withJSONObject: [[
                "garden_epoch": gardenEpoch.uuidString.lowercased(),
                "garden_reset_at": NSNull(),
            ]])
        case ("GET", "/rest/v1/garden_plants"):
            status = 200
            data = try JSONSerialization.data(withJSONObject: [[
                "id": plant.id.uuidString.lowercased(),
                "flower_id": plant.flowerId,
                "nickname": plant.nickname,
                "added_at": "2026-07-21T09:00:00Z",
                "last_watered_at": "2026-07-21T09:00:00Z",
                "status": plant.status.rawValue,
                "notes": plant.notes,
                "updated_at": tombstoned ? "2026-07-21T11:00:00Z" : "2026-07-21T10:00:00Z",
                "deleted_at": tombstoned ? "2026-07-21T11:00:00Z" : NSNull(),
            ]])
        case ("POST", "/rest/v1/garden_plants"):
            status = 201
            data = Data()
        default:
            throw URLError(.unsupportedURL)
        }

        let response = HTTPURLResponse(
            url: url,
            statusCode: status,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        return (response, data)
    }
}

private final class AuthLifecycleRaceScenario: @unchecked Sendable {
    private let condition = NSCondition()
    private let userID: UUID
    private var gardenEpoch: UUID
    private let resetEpoch: UUID
    private let gardenResetAt: String?
    private var failsProfileFetch: Bool
    private var failsGardenPost: Bool
    private var shouldBlockProfileFetch = false
    private var profileFetchIsBlocked = false
    private var profileFetchIsReleased = false
    private var shouldBlockLogout = false
    private var logoutRequestIsBlocked = false
    private var logoutRequestIsReleased = false
    private var shouldBlockGardenReset = false
    private var gardenResetRequestIsBlocked = false
    private var gardenResetRequestIsReleased = false
    private var recordedAuthRequestCount = 0
    private var recordedProfileFetchCount = 0
    private var recordedGardenPostCount = 0
    private var recordedGardenResetCount = 0
    private var recordedGardenEpochs: [UUID] = []
    private var recordedGardenPlantIDs: [UUID] = []
    private var storedGardenRows: [[String: Any]] = []

    init(
        userID: UUID,
        gardenEpoch: UUID,
        gardenResetAt: String?,
        failsProfileFetch: Bool = false,
        failsGardenPost: Bool = false,
        resetEpoch: UUID = UUID()
    ) {
        self.userID = userID
        self.gardenEpoch = gardenEpoch
        self.resetEpoch = resetEpoch
        self.gardenResetAt = gardenResetAt
        self.failsProfileFetch = failsProfileFetch
        self.failsGardenPost = failsGardenPost
    }

    var authRequestCount: Int {
        condition.lock()
        defer { condition.unlock() }
        return recordedAuthRequestCount
    }

    var profileFetchCount: Int {
        condition.lock()
        defer { condition.unlock() }
        return recordedProfileFetchCount
    }

    var gardenPostCount: Int {
        condition.lock()
        defer { condition.unlock() }
        return recordedGardenPostCount
    }

    var gardenResetCount: Int {
        condition.lock()
        defer { condition.unlock() }
        return recordedGardenResetCount
    }

    var postedGardenEpochs: [UUID] {
        condition.lock()
        defer { condition.unlock() }
        return recordedGardenEpochs
    }

    var postedGardenPlantIDs: [UUID] {
        condition.lock()
        defer { condition.unlock() }
        return recordedGardenPlantIDs
    }

    func blockNextProfileFetch() {
        condition.lock()
        shouldBlockProfileFetch = true
        profileFetchIsReleased = false
        condition.unlock()
    }

    func setFailsProfileFetch(_ shouldFail: Bool) {
        condition.lock()
        failsProfileFetch = shouldFail
        condition.unlock()
    }

    func setFailsGardenPost(_ shouldFail: Bool) {
        condition.lock()
        failsGardenPost = shouldFail
        condition.unlock()
    }

    func blockNextLogoutRequest() {
        condition.lock()
        shouldBlockLogout = true
        logoutRequestIsReleased = false
        condition.unlock()
    }

    func blockNextGardenReset() {
        condition.lock()
        shouldBlockGardenReset = true
        gardenResetRequestIsReleased = false
        condition.unlock()
    }

    func waitUntilProfileFetchIsBlocked() async {
        await waitUntil { [self] in
            condition.lock()
            defer { condition.unlock() }
            return profileFetchIsBlocked
        }
    }

    func waitUntilLogoutRequestIsBlocked() async {
        await waitUntil { [self] in
            condition.lock()
            defer { condition.unlock() }
            return logoutRequestIsBlocked
        }
    }

    func waitUntilGardenResetRequestIsBlocked() async {
        await waitUntil { [self] in
            condition.lock()
            defer { condition.unlock() }
            return gardenResetRequestIsBlocked
        }
    }

    func releaseProfileFetch() {
        condition.lock()
        profileFetchIsReleased = true
        condition.broadcast()
        condition.unlock()
    }

    func releaseLogoutRequest() {
        condition.lock()
        logoutRequestIsReleased = true
        condition.broadcast()
        condition.unlock()
    }

    func releaseGardenResetRequest() {
        condition.lock()
        gardenResetRequestIsReleased = true
        condition.broadcast()
        condition.unlock()
    }

    func response(for request: URLRequest) throws -> (HTTPURLResponse, Data) {
        guard let url = request.url else { throw URLError(.badURL) }
        let status: Int
        let data: Data

        switch (request.httpMethod, url.path) {
        case ("POST", "/auth/v1/token"):
            condition.lock()
            recordedAuthRequestCount += 1
            condition.broadcast()
            condition.unlock()
            status = 200
            data = try JSONSerialization.data(withJSONObject: [
                "access_token": "new-access-token",
                "refresh_token": "new-refresh-token",
                "expires_in": 3_600,
                "user": [
                    "id": userID.uuidString.lowercased(),
                    "email": "gardener@example.com",
                ],
            ])
        case ("POST", "/auth/v1/logout"):
            condition.lock()
            if shouldBlockLogout {
                logoutRequestIsBlocked = true
                condition.broadcast()
                while !logoutRequestIsReleased {
                    condition.wait()
                }
                shouldBlockLogout = false
            }
            condition.unlock()
            status = 204
            data = Data()
        case ("POST", "/rest/v1/analytics_events"):
            status = 201
            data = Data()
        case ("POST", "/rest/v1/rpc/reset_my_garden"):
            condition.lock()
            if shouldBlockGardenReset {
                gardenResetRequestIsBlocked = true
                condition.broadcast()
                while !gardenResetRequestIsReleased {
                    condition.wait()
                }
                shouldBlockGardenReset = false
            }
            recordedGardenResetCount += 1
            gardenEpoch = resetEpoch
            storedGardenRows.removeAll()
            let returnedResetEpoch = gardenEpoch
            condition.unlock()
            status = 200
            data = Data("\"\(returnedResetEpoch.uuidString.lowercased())\"".utf8)
        case ("GET", "/rest/v1/profiles"):
            condition.lock()
            recordedProfileFetchCount += 1
            if shouldBlockProfileFetch {
                profileFetchIsBlocked = true
                condition.broadcast()
                while !profileFetchIsReleased {
                    condition.wait()
                }
                shouldBlockProfileFetch = false
            }
            let shouldFailProfileFetch = failsProfileFetch
            condition.unlock()
            if shouldFailProfileFetch {
                status = 503
                data = try JSONSerialization.data(withJSONObject: [
                    "message": "Temporarily unavailable",
                ])
            } else {
                condition.lock()
                let currentGardenEpoch = gardenEpoch
                condition.unlock()
                status = 200
                var profile: [String: Any] = [
                    "garden_epoch": currentGardenEpoch.uuidString.lowercased(),
                ]
                if let gardenResetAt {
                    profile["garden_reset_at"] = gardenResetAt
                } else {
                    profile["garden_reset_at"] = NSNull()
                }
                data = try JSONSerialization.data(withJSONObject: [profile])
            }
        case ("GET", "/rest/v1/garden_plants"):
            condition.lock()
            let rows = storedGardenRows
            condition.unlock()
            status = 200
            data = try JSONSerialization.data(withJSONObject: rows)
        case ("POST", "/rest/v1/garden_plants"):
            guard let postedRows = Self.gardenRows(from: request) else {
                throw URLError(.cannotParseResponse)
            }
            let epochs = postedRows.compactMap { row in
                (row["garden_epoch"] as? String).flatMap(UUID.init(uuidString:))
            }
            let plantIDs = postedRows.compactMap { row in
                (row["id"] as? String).flatMap(UUID.init(uuidString:))
            }
            guard epochs.count == postedRows.count, plantIDs.count == postedRows.count else {
                throw URLError(.cannotParseResponse)
            }
            condition.lock()
            recordedGardenPostCount += 1
            recordedGardenEpochs.append(contentsOf: epochs)
            recordedGardenPlantIDs.append(contentsOf: plantIDs)
            let shouldFailGardenPost = failsGardenPost
            if !shouldFailGardenPost {
                for postedRow in postedRows {
                    guard let id = postedRow["id"] as? String else { continue }
                    var remoteRow = postedRow
                    remoteRow.removeValue(forKey: "garden_epoch")
                    remoteRow["deleted_at"] = NSNull()
                    if let index = storedGardenRows.firstIndex(where: { $0["id"] as? String == id }) {
                        storedGardenRows[index] = remoteRow
                    } else {
                        storedGardenRows.append(remoteRow)
                    }
                }
            }
            condition.unlock()
            status = shouldFailGardenPost ? 503 : 201
            data = shouldFailGardenPost
                ? try JSONSerialization.data(withJSONObject: ["message": "Temporarily unavailable"])
                : Data()
        default:
            throw URLError(.unsupportedURL)
        }

        let response = HTTPURLResponse(
            url: url,
            statusCode: status,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        return (response, data)
    }

    private static func gardenRows(from request: URLRequest) -> [[String: Any]]? {
        guard
            let body = bodyData(from: request),
            let payload = try? JSONSerialization.jsonObject(with: body) as? [[String: Any]]
        else { return nil }
        return payload
    }

    private static func bodyData(from request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        let capacity = 4_096
        var buffer = [UInt8](repeating: 0, count: capacity)
        var body = Data()
        while true {
            let count = buffer.withUnsafeMutableBytes { bytes -> Int in
                guard let base = bytes.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return -1 }
                return stream.read(base, maxLength: capacity)
            }
            guard count > 0 else { break }
            body.append(contentsOf: buffer.prefix(count))
        }
        return body.isEmpty ? nil : body
    }

    private func waitUntil(_ predicate: @escaping () -> Bool) async {
        for _ in 0..<500 {
            if predicate() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for the auth lifecycle test condition")
    }
}

private actor BlockingSessionRefresher {
    private var didStart = false
    private var refreshContinuation: CheckedContinuation<AuthSession, Error>?

    func refresh(_ session: AuthSession) async throws -> AuthSession {
        didStart = true
        return try await withCheckedThrowingContinuation { continuation in
            refreshContinuation = continuation
        }
    }

    func waitUntilStarted() async {
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(5)
        while !didStart, clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(didStart, "Timed out waiting for the session refresh to start")
    }

    func release(returning session: AuthSession) {
        refreshContinuation?.resume(returning: session)
        refreshContinuation = nil
    }
}

private final class BlockingGardenFetchScenario: @unchecked Sendable {
    private let lock = NSLock()
    private let condition = NSCondition()
    private let plant: GardenPlant
    private let gardenEpoch: UUID
    private var gardenFetchIsBlocked = false
    private var gardenFetchIsReleased = false
    private var recordedSignatures: [String] = []

    init(plant: GardenPlant, gardenEpoch: UUID) {
        self.plant = plant
        self.gardenEpoch = gardenEpoch
    }

    var signatures: [String] {
        lock.lock()
        defer { lock.unlock() }
        return recordedSignatures
    }

    func waitUntilGardenFetchIsBlocked() async {
        await waitUntil { [self] in
            condition.lock()
            defer { condition.unlock() }
            return gardenFetchIsBlocked
        }
    }

    @MainActor
    func waitUntil(_ condition: @escaping @MainActor () -> Bool) async {
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(5)
        while clock.now < deadline {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for the garden sync test condition")
    }

    func releaseGardenFetch() {
        condition.lock()
        gardenFetchIsReleased = true
        condition.broadcast()
        condition.unlock()
    }

    func response(for request: URLRequest) throws -> (HTTPURLResponse, Data) {
        guard let url = request.url else { throw URLError(.badURL) }
        let signature = "\(request.httpMethod ?? "GET") \(url.path)"
        lock.lock()
        recordedSignatures.append(signature)
        lock.unlock()

        let status: Int
        let data: Data
        switch (request.httpMethod, url.path) {
        case ("GET", "/rest/v1/profiles"):
            status = 200
            data = try JSONSerialization.data(withJSONObject: [[
                "garden_epoch": gardenEpoch.uuidString.lowercased(),
                "garden_reset_at": NSNull(),
            ]])
        case ("GET", "/rest/v1/garden_plants"):
            condition.lock()
            gardenFetchIsBlocked = true
            condition.broadcast()
            while !gardenFetchIsReleased {
                condition.wait()
            }
            condition.unlock()
            status = 200
            data = try JSONSerialization.data(withJSONObject: [[
                "id": plant.id.uuidString.lowercased(),
                "flower_id": plant.flowerId,
                "nickname": plant.nickname,
                "added_at": "2026-07-21T09:00:00Z",
                "last_watered_at": "2026-07-21T09:00:00Z",
                "status": plant.status.rawValue,
                "notes": plant.notes,
                "updated_at": "2026-07-21T10:00:00Z",
                "deleted_at": NSNull(),
            ]])
        case ("POST", "/auth/v1/logout"):
            status = 204
            data = Data()
        case ("POST", "/rest/v1/garden_plants"):
            status = 201
            data = Data()
        default:
            throw URLError(.unsupportedURL)
        }

        let response = HTTPURLResponse(
            url: url,
            statusCode: status,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        return (response, data)
    }
}
