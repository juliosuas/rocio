import Foundation

enum GardenPersistence {
    private static let plantsKey = "rocio.ios.garden.plants"
    private static let pendingRouteKey = "rocio.ios.pendingIntentRoute"
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    static func loadPlants() -> [GardenPlant] {
        guard let data = UserDefaults.standard.data(forKey: plantsKey) else { return [] }
        return (try? decoder.decode([GardenPlant].self, from: data)) ?? []
    }

    static func savePlants(_ plants: [GardenPlant]) {
        guard let data = try? encoder.encode(plants) else { return }
        UserDefaults.standard.set(data, forKey: plantsKey)
    }

    static func clearPlants() {
        UserDefaults.standard.removeObject(forKey: plantsKey)
    }

    static func setPendingRoute(_ route: IntentRoute) {
        UserDefaults.standard.set(route.rawValue, forKey: pendingRouteKey)
    }

    static func takePendingRoute() -> IntentRoute? {
        guard let raw = UserDefaults.standard.string(forKey: pendingRouteKey) else { return nil }
        UserDefaults.standard.removeObject(forKey: pendingRouteKey)
        return IntentRoute(rawValue: raw)
    }
}

enum IntentRoute: String {
    case garden
    case scanner
    case calendar
}

enum IntentHandoffStore {
    static func setPendingRoute(_ route: IntentRoute) {
        GardenPersistence.setPendingRoute(route)
    }

    static func takePendingRoute() -> IntentRoute? {
        GardenPersistence.takePendingRoute()
    }
}

struct GardenExport: Codable, Equatable {
    let exportedAt: Date
    let appVersion: String
    let bundleIdentifier: String
    let plants: [GardenPlant]

    static func payload(
        plants: [GardenPlant],
        exportedAt: Date = Date(),
        appVersion: String = "1.0",
        bundleIdentifier: String = "com.juliosuas.rocio"
    ) -> String {
        let export = GardenExport(
            exportedAt: exportedAt,
            appVersion: appVersion,
            bundleIdentifier: bundleIdentifier,
            plants: plants
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(export),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }
}
