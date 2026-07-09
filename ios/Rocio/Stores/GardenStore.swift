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

    func summary(now: Date = Date()) -> GardenSummary {
        var overdue = 0
        var soon = 0
        var nextDate: Date?

        for plant in plants {
            switch urgency(for: plant, now: now) {
            case .overdue:
                overdue += 1
            case .soon:
                soon += 1
            case .good:
                break
            }

            let candidate = nextWateringDate(for: plant)
            if let currentNextDate = nextDate {
                if candidate < currentNextDate {
                    nextDate = candidate
                }
            } else {
                nextDate = candidate
            }
        }

        return GardenSummary(
            plantCount: plants.count,
            overdueCount: overdue,
            soonCount: soon,
            nextWateringDate: nextDate
        )
    }

    private func persist() {
        GardenPersistence.savePlants(plants)
    }
}

struct GardenSummary: Equatable {
    let plantCount: Int
    let overdueCount: Int
    let soonCount: Int
    let nextWateringDate: Date?

    var needsAttentionCount: Int {
        overdueCount + soonCount
    }

    var statusLabel: String {
        if plantCount == 0 { return L10n.text("garden.summary.empty", fallback: "No plants yet") }
        if overdueCount > 0 { return L10n.text("garden.summary.overdue", fallback: "Time to water") }
        if soonCount > 0 { return L10n.text("garden.summary.soon", fallback: "Check soon") }
        return L10n.text("garden.summary.good", fallback: "All on track")
    }
}
