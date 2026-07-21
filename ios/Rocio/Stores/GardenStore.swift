import Foundation

@MainActor
final class GardenStore: ObservableObject {
    @Published private(set) var plants: [GardenPlant]
    @Published private(set) var isDemoMode = false
    var cloudChangeHandler: ((GardenChange) -> Void)?
    private var plantsBeforeDemo: [GardenPlant]?

    init(plants: [GardenPlant] = GardenPersistence.loadPlants()) {
        self.plants = plants
    }

    func add(_ flower: Flower) {
        let existing = plants.first { $0.flowerId == flower.id }
        guard existing == nil else { return }
        let plant = GardenPlant(flowerId: flower.id, nickname: flower.name)
        plants.append(plant)
        persist()
        cloudChangeHandler?(.upsert(plant))
    }

    func water(_ plant: GardenPlant, at date: Date = Date()) {
        guard let index = plants.firstIndex(where: { $0.id == plant.id }) else { return }
        plants[index].lastWateredAt = date
        plants[index].updatedAt = date
        if plants[index].status == .needsWater {
            plants[index].status = .healthy
        }
        persist()
        cloudChangeHandler?(.upsert(plants[index]))
    }

    func update(_ plant: GardenPlant, nickname: String, status: PlantStatus, notes: String) {
        guard let index = plants.firstIndex(where: { $0.id == plant.id }) else { return }
        plants[index].nickname = nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? plant.nickname : nickname
        plants[index].status = status
        plants[index].notes = notes
        plants[index].updatedAt = Date()
        persist()
        cloudChangeHandler?(.upsert(plants[index]))
    }

    func delete(_ plant: GardenPlant) {
        plants.removeAll { $0.id == plant.id }
        persist()
        cloudChangeHandler?(.delete(plant.id))
    }

    func reset() {
        plants.removeAll()
        if !isDemoMode {
            GardenPersistence.clearPlants()
        }
        cloudChangeHandler?(.reset)
    }

    func clearLocalCache() {
        plants.removeAll()
        GardenPersistence.clearPlants()
    }

    func reloadFromPersistence() {
        guard !isDemoMode else { return }
        let savedPlants = GardenPersistence.loadPlants()
        guard savedPlants != plants else { return }
        plants = savedPlants
    }

    func replaceFromCloud(_ cloudPlants: [GardenPlant]) {
        guard cloudPlants != plants else { return }
        plants = cloudPlants.sorted { $0.addedAt < $1.addedAt }
        persist()
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
        guard !isDemoMode else { return }
        GardenPersistence.savePlants(plants)
    }

#if DEBUG
    func beginDemo(now: Date = Date()) {
        guard !isDemoMode else { return }
        plantsBeforeDemo = plants
        isDemoMode = true
        plants = Self.demoPlants(now: now)
    }

    func endDemo() {
        guard isDemoMode else { return }
        plants = plantsBeforeDemo ?? GardenPersistence.loadPlants()
        plantsBeforeDemo = nil
        isDemoMode = false
    }

    private static func demoPlants(now: Date) -> [GardenPlant] {
        let calendar = Calendar.current
        func date(daysAgo: Int) -> Date {
            calendar.date(byAdding: .day, value: -daysAgo, to: now) ?? now
        }

        return [
            GardenPlant(
                id: UUID(uuidString: "A10CF2F7-8EC0-4F20-95A7-75FD70D8C101")!,
                flowerId: "rosa",
                nickname: L10n.text("demo.plant.rose", fallback: "Balcony rose"),
                addedAt: date(daysAgo: 42),
                lastWateredAt: date(daysAgo: 5),
                status: .needsWater,
                notes: L10n.text("demo.plant.rose.notes", fallback: "Morning light near the balcony."),
                updatedAt: date(daysAgo: 5)
            ),
            GardenPlant(
                id: UUID(uuidString: "A10CF2F7-8EC0-4F20-95A7-75FD70D8C102")!,
                flowerId: "lavanda",
                nickname: L10n.text("demo.plant.lavender", fallback: "Kitchen lavender"),
                addedAt: date(daysAgo: 24),
                lastWateredAt: date(daysAgo: 1),
                status: .healthy,
                notes: L10n.text("demo.plant.lavender.notes", fallback: "Rotate the pot every weekend."),
                updatedAt: date(daysAgo: 1)
            ),
            GardenPlant(
                id: UUID(uuidString: "A10CF2F7-8EC0-4F20-95A7-75FD70D8C103")!,
                flowerId: "orquidea",
                nickname: L10n.text("demo.plant.orchid", fallback: "Studio orchid"),
                addedAt: date(daysAgo: 16),
                lastWateredAt: date(daysAgo: 6),
                status: .needsSun,
                notes: L10n.text("demo.plant.orchid.notes", fallback: "Keep away from direct afternoon sun."),
                updatedAt: date(daysAgo: 2)
            )
        ]
    }
#endif
}

enum GardenChange {
    case upsert(GardenPlant)
    case delete(UUID)
    case reset
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
