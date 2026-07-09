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

@MainActor
final class AppRouter: ObservableObject {
    @Published var selectedTab: AppTab = .catalog

    func route(_ url: URL) {
        guard url.scheme == "rocio" else { return }
        switch url.host {
        case "garden":
            selectedTab = .garden
        case "scanner":
            selectedTab = .scanner
        case "calendar":
            selectedTab = .calendar
        default:
            selectedTab = .catalog
        }
    }

    func applyPendingIntentRoute() {
        guard let route = IntentHandoffStore.takePendingRoute() else { return }
        switch route {
        case .garden:
            selectedTab = .garden
        case .scanner:
            selectedTab = .scanner
        case .calendar:
            selectedTab = .calendar
        }
    }
}
