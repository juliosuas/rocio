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
        case .catalog: "Catalogo"
        case .garden: "Jardin"
        case .calendar: "Calendario"
        case .scanner: "Scanner"
        case .settings: "Ajustes"
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

