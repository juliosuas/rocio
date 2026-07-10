import XCTest
@testable import Rocio

final class CloudFoundationTests: XCTestCase {
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
