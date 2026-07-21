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

        let payload = GardenPlantUpsertPayload(plant: legacyPlant, userID: UUID())

        XCTAssertEqual(payload.nickname, nicknamePrefix)
        XCTAssertEqual(payload.nickname.unicodeScalars.count, 79)
        XCTAssertEqual(payload.notes, notesPrefix)
        XCTAssertEqual(payload.notes.unicodeScalars.count, 1_999)
        XCTAssertEqual(legacyPlant.nickname, nicknamePrefix + composedEmoji)
        XCTAssertEqual(legacyPlant.notes, notesPrefix + composedEmoji)
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
