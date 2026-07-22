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

struct PasswordRecoveryCallback: Equatable {
    static let redirectURL = URL(string: "com.juliosuas.rocio://auth/recovery")!

    let authorizationCode: String

    static func matches(_ url: URL) -> Bool {
        url.scheme?.lowercased() == redirectURL.scheme?.lowercased()
            && url.host?.lowercased() == redirectURL.host?.lowercased()
            && url.path == redirectURL.path
            && url.user == nil
            && url.password == nil
            && url.port == nil
    }

    static func parse(_ url: URL) throws -> PasswordRecoveryCallback {
        guard matches(url), url.fragment == nil else { throw invalidLink }
        let values = try queryValues(url)

        if values["error"] != nil || values["error_code"] != nil || values["error_description"] != nil {
            throw invalidLink
        }

        guard Set(values.keys) == ["code"], let authorizationCode = nonempty(values["code"]) else {
            throw invalidLink
        }
        return PasswordRecoveryCallback(authorizationCode: authorizationCode)
    }

    private static var invalidLink: BackendError {
        .server(code: "recovery_link_invalid", message: "The password recovery link is invalid or expired.")
    }

    private static func queryValues(_ url: URL) throws -> [String: String] {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw invalidLink
        }
        guard let items = components.queryItems, !items.isEmpty else { throw invalidLink }

        var values: [String: String] = [:]
        for item in items {
            guard values[item.name] == nil, let value = item.value else { throw invalidLink }
            values[item.name] = value
        }
        return values
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}

enum BackendError: LocalizedError, Equatable {
    case unavailable
    case invalidResponse
    case server(code: String, message: String)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            L10n.text("error.cloud.generic", fallback: "Rocio Cloud is temporarily unavailable. Try again.")
        case .invalidResponse:
            L10n.text("error.cloud.generic", fallback: "Rocio Cloud is temporarily unavailable. Try again.")
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
            case "same_password":
                L10n.text("error.auth.same_password", fallback: "Choose a password you have not used for this account.")
            case "recovery_link_invalid", "otp_expired", "invalid_token", "bad_jwt", "token_expired",
                 "bad_code_verifier", "flow_state_expired", "flow_state_not_found":
                L10n.text("error.auth.recovery_link", fallback: "This password reset link is invalid or expired. Request a new one.")
            case "over_email_send_rate_limit", "email_rate_limit_exceeded", "over_request_rate_limit":
                L10n.text("error.auth.recovery_rate", fallback: "Too many reset emails were requested. Wait a few minutes and try again.")
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
