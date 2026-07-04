import AppIntents
import Foundation

struct GardenPlantEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Planta de Rocio")
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
    static let title: LocalizedStringResource = "Abrir Mi Jardin"
    static let description = IntentDescription("Abre Rocio directamente en Mi Jardin.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult & ProvidesDialog {
        IntentHandoffStore.setPendingRoute(.garden)
        return .result(dialog: "Abriendo Mi Jardin en Rocio.")
    }
}

struct OpenScannerIntent: AppIntent {
    static let title: LocalizedStringResource = "Escanear una flor"
    static let description = IntentDescription("Abre el scanner de Rocio para tomar o elegir una foto.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult & ProvidesDialog {
        IntentHandoffStore.setPendingRoute(.scanner)
        return .result(dialog: "Abriendo el scanner de Rocio.")
    }
}

struct LogWateringIntent: AppIntent {
    static let title: LocalizedStringResource = "Registrar riego"
    static let description = IntentDescription("Marca una planta guardada como regada.")
    static let openAppWhenRun = false

    @Parameter(title: "Planta")
    var plant: GardenPlantEntity

    func perform() async throws -> some IntentResult & ProvidesDialog {
        var plants = GardenPersistence.loadPlants()
        guard let uuid = UUID(uuidString: plant.id),
              let index = plants.firstIndex(where: { $0.id == uuid }) else {
            return .result(dialog: "No encontre esa planta en Mi Jardin.")
        }
        plants[index].lastWateredAt = Date()
        if plants[index].status == .needsWater {
            plants[index].status = .healthy
        }
        GardenPersistence.savePlants(plants)
        return .result(dialog: "Listo. Registre el riego de \(plants[index].nickname).")
    }
}

struct RocioShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenGardenIntent(),
            phrases: [
                "Abre mi jardin en \(.applicationName)",
                "Ver mi jardin en \(.applicationName)"
            ],
            shortTitle: "Abrir jardin",
            systemImageName: "leaf"
        )

        AppShortcut(
            intent: LogWateringIntent(),
            phrases: [
                "Regar una planta en \(.applicationName)",
                "Registrar riego en \(.applicationName)"
            ],
            shortTitle: "Registrar riego",
            systemImageName: "drop"
        )

        AppShortcut(
            intent: OpenScannerIntent(),
            phrases: [
                "Escanear una flor con \(.applicationName)",
                "Identificar una flor en \(.applicationName)"
            ],
            shortTitle: "Escanear flor",
            systemImageName: "camera.viewfinder"
        )
    }
}

