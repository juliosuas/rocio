import Foundation

@MainActor
final class GardenStore: ObservableObject {
    @Published private(set) var plants: [GardenPlant]

    init(plants: [GardenPlant] = GardenPersistence.loadPlants()) {
        self.plants = plants
    }

    func add(_ flower: Flower) {
        let existing = plants.first { $0.flowerId == flower.id }
        guard existing == nil else { return }
        plants.append(GardenPlant(flowerId: flower.id, nickname: flower.name))
        persist()
    }

    func water(_ plant: GardenPlant, at date: Date = Date()) {
        guard let index = plants.firstIndex(where: { $0.id == plant.id }) else { return }
        plants[index].lastWateredAt = date
        if plants[index].status == .needsWater {
            plants[index].status = .healthy
        }
        persist()
    }

    func update(_ plant: GardenPlant, nickname: String, status: PlantStatus, notes: String) {
        guard let index = plants.firstIndex(where: { $0.id == plant.id }) else { return }
        plants[index].nickname = nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? plant.nickname : nickname
        plants[index].status = status
        plants[index].notes = notes
        persist()
    }

    func delete(_ plant: GardenPlant) {
        plants.removeAll { $0.id == plant.id }
        persist()
    }

    func reset() {
        plants.removeAll()
        GardenPersistence.clearPlants()
    }

    func reloadFromPersistence() {
        let savedPlants = GardenPersistence.loadPlants()
        guard savedPlants != plants else { return }
        plants = savedPlants
    }

    func flower(for plant: GardenPlant) -> Flower? {
        FlowerCatalog.flower(id: plant.flowerId)
    }

    func urgency(for plant: GardenPlant, now: Date = Date()) -> WateringUrgency {
        guard let flower = flower(for: plant) else { return .good }
        let days = Calendar.current.dateComponents([.day], from: plant.lastWateredAt, to: now).day ?? 0
        if days >= flower.waterDays { return .overdue }
        if days >= max(0, flower.waterDays - 1) { return .soon }
        return .good
    }

    func nextWateringDate(for plant: GardenPlant) -> Date {
        let days = flower(for: plant)?.waterDays ?? 3
        return Calendar.current.date(byAdding: .day, value: days, to: plant.lastWateredAt) ?? plant.lastWateredAt
    }

    private func persist() {
        GardenPersistence.savePlants(plants)
    }
}
