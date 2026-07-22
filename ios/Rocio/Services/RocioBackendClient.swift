import Foundation
import UIKit

actor RocioBackendClient {
    private let configuration: BackendConfiguration
    private let urlSession: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(configuration: BackendConfiguration, urlSession: URLSession = .shared) {
        self.configuration = configuration
        self.urlSession = urlSession
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            try Self.decodeDate(decoder)
        }
        self.decoder = decoder
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
    }

    func signIn(email: String, password: String) async throws -> AuthSession {
        let payload = Credentials(email: email, password: password)
        let request = try request(path: "/auth/v1/token?grant_type=password", method: "POST", body: payload)
        return try await authSession(for: request)
    }

    func signUp(email: String, password: String, locale: String) async throws -> AuthSession {
        let payload = SignUpPayload(email: email, password: password, data: ["locale": locale])
        let request = try request(path: "/auth/v1/signup", method: "POST", body: payload)
        return try await authSession(for: request)
    }

    func requestPasswordReset(email: String, codeChallenge: String) async throws {
        let endpoint = configuration.baseURL
            .appendingPathComponent("auth")
            .appendingPathComponent("v1")
            .appendingPathComponent("recover")
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw BackendError.invalidResponse
        }
        components.queryItems = [
            URLQueryItem(name: "redirect_to", value: PasswordRecoveryCallback.redirectURL.absoluteString),
        ]
        guard let url = components.url else { throw BackendError.invalidResponse }
        let request = try request(
            url: url,
            method: "POST",
            body: PasswordResetPayload(
                email: email,
                codeChallenge: codeChallenge,
                codeChallengeMethod: "s256"
            )
        )
        _ = try await responseData(for: request)
    }

    func recoverySession(from callback: PasswordRecoveryCallback, codeVerifier: String) async throws -> AuthSession {
        let exchangeRequest = try request(
            path: "/auth/v1/token?grant_type=pkce",
            method: "POST",
            body: PasswordRecoveryExchangePayload(
                authCode: callback.authorizationCode,
                codeVerifier: codeVerifier
            )
        )
        // The PKCE authorization code is single-use. authSession(for:) already
        // requires a valid user id and email in Supabase's token response, so a
        // second request would only add a fallible step after consuming the code.
        return try await authSession(for: exchangeRequest)
    }

    func updatePassword(_ password: String, session: AuthSession) async throws {
        let request = try request(
            path: "/auth/v1/user",
            method: "PUT",
            token: session.accessToken,
            body: PasswordUpdatePayload(password: password)
        )
        let data = try await responseData(for: request)
        let response = try decoder.decode(AuthUserResponse.self, from: data)
        guard UUID(uuidString: response.id) == session.user.id else {
            throw BackendError.invalidResponse
        }
    }

    func refresh(_ session: AuthSession) async throws -> AuthSession {
        let payload = RefreshPayload(refreshToken: session.refreshToken)
        let request = try request(path: "/auth/v1/token?grant_type=refresh_token", method: "POST", body: payload)
        return try await authSession(for: request)
    }

    func signOut(session: AuthSession) async {
        guard let request = try? request(path: "/auth/v1/logout?scope=local", method: "POST", token: session.accessToken) else { return }
        _ = try? await urlSession.data(for: request)
    }

    func deleteAccount(session: AuthSession) async throws {
        let request = try request(path: "/rest/v1/rpc/delete_my_account", method: "POST", token: session.accessToken, body: EmptyPayload())
        _ = try await responseData(for: request)
    }

    func fetchGarden(session: AuthSession) async throws -> [CloudGardenRecord] {
        let query = "/rest/v1/garden_plants?select=id,flower_id,nickname,added_at,last_watered_at,status,notes,updated_at,deleted_at&order=updated_at.desc"
        let request = try request(path: query, method: "GET", token: session.accessToken)
        let data = try await responseData(for: request)
        return try decoder.decode([CloudGardenRecord].self, from: data)
    }

    func fetchGardenSyncState(session: AuthSession) async throws -> CloudGardenSyncState {
        let query = "/rest/v1/profiles?select=garden_epoch,garden_reset_at&limit=1"
        let request = try request(path: query, method: "GET", token: session.accessToken)
        let data = try await responseData(for: request)
        guard let state = try decoder.decode([CloudGardenSyncState].self, from: data).first else {
            throw BackendError.invalidResponse
        }
        return state
    }

    func upsertGarden(_ plants: [GardenPlant], gardenEpoch: UUID, session: AuthSession) async throws {
        guard !plants.isEmpty else { return }
        let payload = plants.map {
            GardenPlantUpsertPayload(
                plant: $0,
                userID: session.user.id,
                gardenEpoch: gardenEpoch
            )
        }
        var request = try request(path: "/rest/v1/garden_plants?on_conflict=id", method: "POST", token: session.accessToken, body: payload)
        request.setValue("resolution=merge-duplicates,return=minimal", forHTTPHeaderField: "Prefer")
        _ = try await responseData(for: request)
    }

    func deletePlant(id: UUID, deletedAt: Date, session: AuthSession) async throws {
        let payload = GardenDeletionPayload(deletedAt: deletedAt, updatedAt: deletedAt)
        let request = try request(
            path: "/rest/v1/garden_plants?id=eq.\(id.uuidString.lowercased())",
            method: "PATCH",
            token: session.accessToken,
            body: payload
        )
        _ = try await responseData(for: request)
    }

    func resetGarden(requestID: UUID, session: AuthSession) async throws -> UUID {
        let request = try request(
            path: "/rest/v1/rpc/reset_my_garden",
            method: "POST",
            token: session.accessToken,
            body: GardenResetPayload(requestID: requestID)
        )
        let data = try await responseData(for: request)
        return try decoder.decode(UUID.self, from: data)
    }

    func identify(image: UIImage, session: AuthSession) async throws -> RemoteIdentificationResponse {
        guard let resized = image.resizedForCloudScan(maxDimension: 1280),
              let jpeg = resized.jpegData(compressionQuality: 0.72) else {
            throw BackendError.invalidResponse
        }
        let payload = ScanPayload(image: jpeg.base64EncodedString(), consent: true)
        let request = try request(path: "/functions/v1/identify-flower", method: "POST", token: session.accessToken, body: payload)
        let data = try await responseData(for: request)
        return try decoder.decode(RemoteIdentificationResponse.self, from: data)
    }

    func track(name: String, properties: [String: String], session: AuthSession) async {
        let payload = AnalyticsPayload(userID: session.user.id, name: name, properties: properties)
        guard let request = try? request(path: "/rest/v1/analytics_events", method: "POST", token: session.accessToken, body: payload) else { return }
        _ = try? await responseData(for: request)
    }

    func setAnalyticsEnabled(_ enabled: Bool, session: AuthSession) async throws {
        let payload = AnalyticsPreferencePayload(enabled: enabled)
        let request = try request(path: "/rest/v1/rpc/set_analytics_enabled", method: "POST", token: session.accessToken, body: payload)
        _ = try await responseData(for: request)
    }

    private func authSession(for request: URLRequest) async throws -> AuthSession {
        let data = try await responseData(for: request)
        let response = try decoder.decode(AuthResponse.self, from: data)
        guard let accessToken = response.accessToken,
              let refreshToken = response.refreshToken,
              let expiresIn = response.expiresIn,
              let user = response.user,
              let email = user.email,
              let id = UUID(uuidString: user.id) else {
            throw BackendError.server(code: "email_confirmation_required", message: "Check your email to confirm the account, then sign in.")
        }
        return AuthSession(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(expiresIn)),
            user: AuthUser(id: id, email: email)
        )
    }

    private func request<T: Encodable>(path: String, method: String, token: String? = nil, body: T) throws -> URLRequest {
        var request = try request(path: path, method: method, token: token)
        request.httpBody = try encoder.encode(body)
        return request
    }

    private func request<T: Encodable>(url: URL, method: String, token: String? = nil, body: T) throws -> URLRequest {
        var request = request(url: url, method: method, token: token)
        request.httpBody = try encoder.encode(body)
        return request
    }

    private func request(path: String, method: String, token: String? = nil) throws -> URLRequest {
        guard let url = URL(string: path, relativeTo: configuration.baseURL) else { throw BackendError.invalidResponse }
        return request(url: url, method: method, token: token)
    }

    private func request(url: URL, method: String, token: String? = nil) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 25
        request.setValue(configuration.anonymousKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        return request
    }

    private func responseData(for request: URLRequest) async throws -> Data {
        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw BackendError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let error = try? decoder.decode(ServerError.self, from: data)
            throw BackendError.server(
                code: error?.errorCode ?? error?.error ?? "http_\(http.statusCode)",
                message: error?.message ?? error?.msg ?? Self.message(for: http.statusCode)
            )
        }
        return data
    }

    private static func decodeDate(_ decoder: Decoder) throws -> Date {
        let value = try decoder.singleValueContainer().decode(String.self)
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        let standard = ISO8601DateFormatter()
        if let date = standard.date(from: value) { return date }
        throw DecodingError.dataCorruptedError(in: try decoder.singleValueContainer(), debugDescription: "Invalid ISO-8601 date")
    }

    private static func message(for status: Int) -> String {
        switch status {
        case 401: "Your session expired. Sign in again."
        case 429: "You have used this month's free scans."
        default: "Rocio Cloud is temporarily unavailable."
        }
    }
}
private struct Credentials: Encodable { let email: String; let password: String }
private struct RefreshPayload: Encodable { let refreshToken: String }
private struct SignUpPayload: Encodable { let email: String; let password: String; let data: [String: String] }
struct PasswordResetPayload: Encodable, Equatable {
    let email: String
    let codeChallenge: String
    let codeChallengeMethod: String
}
struct PasswordRecoveryExchangePayload: Encodable, Equatable {
    let authCode: String
    let codeVerifier: String
}
struct PasswordUpdatePayload: Encodable, Equatable { let password: String }
private struct EmptyPayload: Encodable {}
private struct GardenResetPayload: Encodable { let requestID: UUID }
struct GardenDeletionPayload: Encodable, Equatable {
    let deletedAt: Date
    let updatedAt: Date
}
private struct ScanPayload: Encodable { let image: String; let consent: Bool }
private struct AnalyticsPayload: Encodable { let userID: UUID; let name: String; let properties: [String: String] }
private struct AnalyticsPreferencePayload: Encodable { let enabled: Bool }

private struct AuthResponse: Decodable {
    let accessToken: String?
    let refreshToken: String?
    let expiresIn: Int?
    let user: User?
    struct User: Decodable { let id: String; let email: String? }
}

private struct AuthUserResponse: Decodable {
    let id: String
    let email: String?
}

private struct ServerError: Decodable {
    let errorCode: String?
    let error: String?
    let message: String?
    let msg: String?
}

struct GardenPlantUpsertPayload: Encodable {
    let id: UUID
    let userID: UUID
    let flowerID: String
    let nickname: String
    let addedAt: Date
    let lastWateredAt: Date
    let status: String
    let notes: String
    let updatedAt: Date
    let gardenEpoch: UUID

    init(plant: GardenPlant, userID: UUID, gardenEpoch: UUID) {
        let normalizedPlant = plant.normalizingTextFields()
        id = normalizedPlant.id
        self.userID = userID
        flowerID = normalizedPlant.flowerId
        nickname = normalizedPlant.nickname
        addedAt = normalizedPlant.addedAt
        lastWateredAt = normalizedPlant.lastWateredAt
        status = normalizedPlant.status.rawValue
        notes = normalizedPlant.notes
        updatedAt = normalizedPlant.updatedAt
        self.gardenEpoch = gardenEpoch
    }
}

struct CloudGardenSyncState: Decodable, Equatable {
    let gardenEpoch: UUID
    let gardenResetAt: Date?
}

struct CloudGardenRecord: Decodable, Equatable {
    let id: UUID
    // JSONDecoder.convertFromSnakeCase maps user_id/flower_id to Id, not ID.
    // Keep these DTO names aligned with that behavior so production responses
    // decode without custom per-field workarounds.
    let userId: UUID?
    let flowerId: String
    let nickname: String
    let addedAt: Date
    let lastWateredAt: Date
    let status: String
    let notes: String
    let updatedAt: Date
    let deletedAt: Date?

    init(plant: GardenPlant, userID: UUID? = nil, deletedAt: Date?) {
        id = plant.id
        userId = userID
        flowerId = plant.flowerId
        nickname = plant.nickname
        addedAt = plant.addedAt
        lastWateredAt = plant.lastWateredAt
        status = plant.status.rawValue
        notes = plant.notes
        updatedAt = plant.updatedAt
        self.deletedAt = deletedAt
    }

    var gardenPlant: GardenPlant {
        GardenPlant(
            id: id,
            flowerId: flowerId,
            nickname: nickname,
            addedAt: addedAt,
            lastWateredAt: lastWateredAt,
            status: PlantStatus(rawValue: status) ?? .healthy,
            notes: notes,
            updatedAt: updatedAt
        )
    }
}

struct RemoteIdentificationResponse: Decodable, Equatable {
    let provider: String
    let suggestions: [Suggestion]
    let quota: Int
    let remaining: Int

    struct Suggestion: Decodable, Equatable {
        let name: String
        let probability: Double
        let scientificName: String
        let commonNames: [String]
        let synonyms: [String]
    }
}

private extension UIImage {
    func resizedForCloudScan(maxDimension: CGFloat) -> UIImage? {
        let largest = max(size.width, size.height)
        guard largest > 0 else { return nil }
        guard largest > maxDimension else { return self }
        let scale = maxDimension / largest
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: target)
        return renderer.image { _ in draw(in: CGRect(origin: .zero, size: target)) }
    }
}
