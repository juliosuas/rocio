import Foundation

struct BackendConfiguration: Equatable {
    let baseURL: URL
    let anonymousKey: String

    static var bundled: BackendConfiguration? {
        guard
            let rawURL = Bundle.main.object(forInfoDictionaryKey: "ROCIOSupabaseURL") as? String,
            let url = URL(string: rawURL),
            let key = Bundle.main.object(forInfoDictionaryKey: "ROCIOSupabaseAnonKey") as? String,
            !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            !key.contains("$(")
        else { return nil }
        return BackendConfiguration(baseURL: url, anonymousKey: key)
    }
}
enum BackendError: LocalizedError, Equatable {
    case unavailable
    case invalidResponse
    case server(code: String, message: String)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "Rocio Cloud is not configured in this build."
        case .invalidResponse:
            "Rocio Cloud returned an invalid response."
        case let .server(_, message):
            message
        }
    }
}
