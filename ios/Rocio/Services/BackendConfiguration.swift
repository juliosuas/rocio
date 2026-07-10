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
        case let .server(code, _):
            switch code {
            case "invalid_credentials":
                L10n.text("error.auth.invalid", fallback: "The email or password is incorrect.")
            case "email_not_confirmed", "email_confirmation_required":
                L10n.text("error.auth.confirm", fallback: "Confirm your email, then sign in.")
            case "user_already_exists", "email_exists", "user_already_registered":
                L10n.text("error.auth.exists", fallback: "An account already exists for this email.")
            case "weak_password":
                L10n.text("error.auth.weak_password", fallback: "Use a password with at least eight characters.")
            case "quota_exhausted", "http_429":
                L10n.text("error.scan.quota", fallback: "You have used this month's cloud scans.")
            case "invalid_session", "http_401":
                L10n.text("error.auth.session", fallback: "Your session expired. Sign in again.")
            default:
                L10n.text("error.cloud.generic", fallback: "Rocio Cloud is temporarily unavailable. Try again.")
            }
        }
    }
}
