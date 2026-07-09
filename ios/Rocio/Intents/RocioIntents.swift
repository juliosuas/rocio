import AppIntents
import Foundation

struct GardenPlantEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Rocio plant")
    static let defaultQuery = GardenPlantQuery()

    let id: String
    let name: String
    let flowerName: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: "\(flowerName)",
            image: .init(systemName: "leaf")
        )
    }
}

struct GardenPlantQuery: EntityQuery {
    func entities(for identifiers: [GardenPlantEntity.ID]) async throws -> [GardenPlantEntity] {
        allEntities().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [GardenPlantEntity] {
        allEntities()
    }

    private func allEntities() -> [GardenPlantEntity] {
        GardenPersistence.loadPlants().compactMap { plant in
            guard let flower = FlowerCatalog.flower(id: plant.flowerId) else { return nil }
            return GardenPlantEntity(id: plant.id.uuidString, name: plant.nickname, flowerName: flower.name)
        }
    }
}

struct OpenGardenIntent: AppIntent {
    static let title: LocalizedStringResource = "Open My Garden"
    static let description = IntentDescription("Open Rocio directly in My Garden.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult & ProvidesDialog {
        IntentHandoffStore.setPendingRoute(.garden)
        return .result(dialog: "Opening My Garden in Rocio.")
    }
}

struct OpenScannerIntent: AppIntent {
    static let title: LocalizedStringResource = "Scan a flower"
    static let description = IntentDescription("Open Rocio's scanner to take or choose a photo.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult & ProvidesDialog {
        IntentHandoffStore.setPendingRoute(.scanner)
        return .result(dialog: "Opening Rocio's scanner.")
    }
}

struct LogWateringIntent: AppIntent {
    static let title: LocalizedStringResource = "Log watering"
    static let description = IntentDescription("Mark a saved plant as watered.")
    static let openAppWhenRun = false

    @Parameter(title: "Plant")
    var plant: GardenPlantEntity

    func perform() async throws -> some IntentResult & ProvidesDialog {
        var plants = GardenPersistence.loadPlants()
        guard let uuid = UUID(uuidString: plant.id),
              let index = plants.firstIndex(where: { $0.id == uuid }) else {
            return .result(dialog: "I could not find that plant in My Garden.")
        }
        plants[index].lastWateredAt = Date()
        if plants[index].status == .needsWater {
            plants[index].status = .healthy
        }
        GardenPersistence.savePlants(plants)
        return .result(dialog: "Done. I logged watering for \(plants[index].nickname).")
    }
}

struct RocioShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenGardenIntent(),
            phrases: [
                "Open my garden in \(.applicationName)",
                "Show my garden in \(.applicationName)"
            ],
            shortTitle: "Open garden",
            systemImageName: "leaf"
        )

        AppShortcut(
            intent: LogWateringIntent(),
            phrases: [
                "Water a plant in \(.applicationName)",
                "Log watering in \(.applicationName)"
            ],
            shortTitle: "Log watering",
            systemImageName: "drop"
        )

        AppShortcut(
            intent: OpenScannerIntent(),
            phrases: [
                "Scan a flower with \(.applicationName)",
                "Identify a flower in \(.applicationName)"
            ],
            shortTitle: "Scan flower",
            systemImageName: "camera.viewfinder"
        )
    }
}
