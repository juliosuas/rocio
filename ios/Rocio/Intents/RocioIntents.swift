import AppIntents
import Foundation

struct GardenPlantEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Rocio plant")
    static let defaultQuery = GardenPlantQuery()

    let id: String
    let name: String
    let plantName: String

    init(plant: GardenPlant) {
        id = plant.id.uuidString
        name = plant.displayName
        plantName = plant.identity.scientificName ?? plant.identity.commonName
    }

    init(id: String, name: String, plantName: String) {
        self.id = id
        self.name = name
        self.plantName = plantName
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: "\(plantName)",
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
        GardenPersistence.loadPlantsForAuthenticatedSession()
            .map(GardenPlantEntity.init(plant:))
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
    static let title: LocalizedStringResource = "Scan a plant"
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
        try await perform(sessionLoader: KeychainSessionStore.load)
    }

    func perform(
        sessionLoader: () -> AuthSession?
    ) async throws -> some IntentResult & ProvidesDialog {
        guard let uuid = UUID(uuidString: plant.id) else {
            return .result(dialog: "I could not find that plant in My Garden.")
        }
        let now = Date()
        let result = GardenPersistence.updatePlantForAuthenticatedSession(
            id: uuid,
            sessionLoader: sessionLoader
        ) { savedPlant in
            savedPlant.lastWateredAt = now
            savedPlant.updatedAt = now
            if savedPlant.status == .needsWater {
                savedPlant.status = .healthy
            }
        }
        switch result {
        case let .updated(updatedPlant):
            return .result(
                dialog: "Done. I logged watering for \(updatedPlant.nickname)."
            )
        case .notFound:
            return .result(dialog: "I could not find that plant in My Garden.")
        case .persistenceFailure:
            return .result(
                dialog: "I could not save that watering update. Open Rocio and try again."
            )
        }
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
                "Scan a plant with \(.applicationName)",
                "Identify a plant in \(.applicationName)"
            ],
            shortTitle: "Scan plant",
            systemImageName: "camera.viewfinder"
        )
    }
}
