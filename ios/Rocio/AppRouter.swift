import Foundation

enum AppTab: String, CaseIterable, Identifiable {
    case catalog
    case garden
    case calendar
    case scanner
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .catalog: L10n.text("tab.catalog", fallback: "Catalog")
        case .garden: L10n.text("tab.garden", fallback: "Garden")
        case .calendar: L10n.text("tab.calendar", fallback: "Calendar")
        case .scanner: L10n.text("tab.scanner", fallback: "Scanner")
        case .settings: L10n.text("tab.settings", fallback: "Settings")
        }
    }

    var systemImage: String {
        switch self {
        case .catalog: "camera.macro"
        case .garden: "leaf"
        case .calendar: "calendar"
        case .scanner: "camera.viewfinder"
        case .settings: "gearshape"
        }
    }
}

enum AppAuthenticationIdentity: Equatable {
    case user(UUID)
#if DEBUG
    case demo
#endif
}

@MainActor
final class AppRouter: ObservableObject {
    // Returning gardeners land on the habit loop. First-time onboarding still
    // routes explicitly to Catalog so they can choose their first flower.
    @Published var selectedTab: AppTab = .garden
    private var pendingAuthenticatedTab: AppTab?
    private var preparedAuthenticatedIdentity: AppAuthenticationIdentity?
    private var suspendedAuthenticatedIdentity: AppAuthenticationIdentity?

    @discardableResult
    func route(_ url: URL, authenticatedIdentity: AppAuthenticationIdentity?) -> Bool {
        guard url.scheme == "rocio" else { return false }
        let destination: AppTab
        switch url.host {
        case "garden":
            destination = .garden
        case "scanner":
            destination = .scanner
        case "calendar":
            destination = .calendar
        default:
            return false
        }
        selectedTab = destination
        pendingAuthenticatedTab = authenticatedIdentity != nil
            && authenticatedIdentity == preparedAuthenticatedIdentity
            ? nil
            : destination
        return true
    }

    func applyPendingIntentRoute(authenticatedIdentity: AppAuthenticationIdentity?) {
        guard let route = IntentHandoffStore.takePendingRoute() else { return }
        let destination: AppTab
        switch route {
        case .garden:
            destination = .garden
        case .scanner:
            destination = .scanner
        case .calendar:
            destination = .calendar
        }
        selectedTab = destination
        pendingAuthenticatedTab = authenticatedIdentity != nil
            && authenticatedIdentity == preparedAuthenticatedIdentity
            ? nil
            : destination
    }

    func prepareForAuthenticatedSession(
        _ identity: AppAuthenticationIdentity,
        hasSeenOnboarding: Bool
    ) {
        guard preparedAuthenticatedIdentity != identity else { return }
        preparedAuthenticatedIdentity = identity
        guard hasSeenOnboarding else {
            pendingAuthenticatedTab = nil
            selectedTab = .catalog
            return
        }
        if let pendingAuthenticatedTab {
            selectedTab = pendingAuthenticatedTab
            self.pendingAuthenticatedTab = nil
        } else {
            selectedTab = .garden
        }
    }

    func restoreAuthenticatedSession(
        _ identity: AppAuthenticationIdentity,
        hasSeenOnboarding: Bool
    ) {
        guard preparedAuthenticatedIdentity != identity else { return }
        preparedAuthenticatedIdentity = identity
        guard hasSeenOnboarding else {
            pendingAuthenticatedTab = nil
            selectedTab = .catalog
            return
        }
        guard let pendingAuthenticatedTab else { return }
        selectedTab = pendingAuthenticatedTab
        self.pendingAuthenticatedTab = nil
    }

    func beginAuthenticatedTransition(from identity: AppAuthenticationIdentity) {
        if preparedAuthenticatedIdentity == identity {
            preparedAuthenticatedIdentity = nil
        }
        suspendedAuthenticatedIdentity = identity
    }

    func endAuthenticatedSession(_ identity: AppAuthenticationIdentity) {
        if preparedAuthenticatedIdentity == identity {
            preparedAuthenticatedIdentity = nil
        }
        if suspendedAuthenticatedIdentity == identity {
            suspendedAuthenticatedIdentity = nil
        }
    }

    func handleSessionTransition(
        from oldState: SessionStore.State,
        to newState: SessionStore.State,
        hasSeenOnboarding: Bool
    ) {
        let oldIdentity = Self.identity(for: oldState)
        let newIdentity = Self.identity(for: newState)

        if let oldIdentity, case .checking = newState {
            beginAuthenticatedTransition(from: oldIdentity)
            return
        }

        if Self.endsAuthenticatedContext(newState) {
            if let endedIdentity = oldIdentity ?? suspendedAuthenticatedIdentity {
                endAuthenticatedSession(endedIdentity)
            }
            return
        }

        if let oldIdentity, let newIdentity, oldIdentity != newIdentity {
            suspendedAuthenticatedIdentity = nil
            prepareForAuthenticatedSession(newIdentity, hasSeenOnboarding: hasSeenOnboarding)
            return
        }

        guard oldIdentity == nil, let newIdentity else { return }

        // Multiple scenes observe the same shared SessionStore. The first
        // scene performs the transition; later observers must be idempotent.
        guard preparedAuthenticatedIdentity != newIdentity else {
            // A later scene may replay the old account's suspend event after
            // another scene already prepared this identity. No suspended
            // identity remains valid once the destination is prepared.
            suspendedAuthenticatedIdentity = nil
            return
        }

        let restoresExistingSession = suspendedAuthenticatedIdentity == newIdentity
        suspendedAuthenticatedIdentity = nil
        if restoresExistingSession {
            restoreAuthenticatedSession(newIdentity, hasSeenOnboarding: hasSeenOnboarding)
        } else {
            prepareForAuthenticatedSession(newIdentity, hasSeenOnboarding: hasSeenOnboarding)
        }
    }

    private static func identity(for state: SessionStore.State) -> AppAuthenticationIdentity? {
        switch state {
        case let .signedIn(session):
            .user(session.user.id)
#if DEBUG
        case .demo:
            .demo
#endif
        case .checking, .unconfigured, .signedOut,
             .recoveringPassword, .passwordUpdated, .passwordUpdatedRequiresSignIn:
            nil
        }
    }

    private static func endsAuthenticatedContext(_ state: SessionStore.State) -> Bool {
        switch state {
        case .unconfigured, .signedOut, .passwordUpdatedRequiresSignIn:
            true
        case .checking, .recoveringPassword, .passwordUpdated, .signedIn:
            false
#if DEBUG
        case .demo:
            false
#endif
        }
    }
}
