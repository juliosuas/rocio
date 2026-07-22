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
        cloudChangeHandler?(.create(plant))
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
        let previousNickname = plants[index].nickname
        var updatedPlant = plants[index]
        updatedPlant.nickname = nickname
        updatedPlant.status = status
        updatedPlant.notes = notes
        updatedPlant.updatedAt = Date()
        plants[index] = updatedPlant.normalizingTextFields(nicknameFallback: previousNickname)
        persist()
        cloudChangeHandler?(.upsert(plants[index]))
    }

    func delete(_ plant: GardenPlant, at date: Date = Date()) {
        plants.removeAll { $0.id == plant.id }
        persist()
        cloudChangeHandler?(.delete(plant.id, at: date))
    }

    func reset(at date: Date = Date()) {
        plants.removeAll()
        if !isDemoMode {
            GardenPersistence.clearPlants()
        }
        cloudChangeHandler?(.reset(at: date))
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
        let normalizedPlants = cloudPlants
            .map { $0.normalizingTextFields() }
            .sorted { $0.addedAt < $1.addedAt }
        guard normalizedPlants != plants else { return }
        plants = normalizedPlants
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

    func nextWateringDate(for plant: GardenPlant, calendar: Calendar = .current) -> Date {
        let days = flower(for: plant)?.waterDays ?? 3
        return calendar.date(byAdding: .day, value: days, to: plant.lastWateredAt) ?? plant.lastWateredAt
    }

    func wateringSchedule(
        startingAt date: Date = Date(),
        dayCount: Int = 7,
        calendar: Calendar = .current
    ) -> WateringSchedule {
        let start = calendar.startOfDay(for: date)
        let dates = (0..<max(0, dayCount)).compactMap {
            calendar.date(byAdding: .day, value: $0, to: start)
        }
        let scheduledPlants = plants.map { plant in
            (plant: plant, dueDate: nextWateringDate(for: plant, calendar: calendar))
        }
        let overduePlants = scheduledPlants.compactMap {
            $0.dueDate < start ? $0.plant : nil
        }
        let days = dates.map { day in
            WateringScheduleDay(
                date: day,
                plants: scheduledPlants.compactMap {
                    calendar.isDate($0.dueDate, inSameDayAs: day) ? $0.plant : nil
                }
            )
        }

        return WateringSchedule(overduePlants: overduePlants, days: days)
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
    case create(GardenPlant)
    case upsert(GardenPlant)
    case delete(UUID, at: Date)
    case reset(at: Date)
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

struct WateringSchedule {
    let overduePlants: [GardenPlant]
    let days: [WateringScheduleDay]

    var totalDueCount: Int {
        overduePlants.count + days.reduce(0) { $0 + $1.plants.count }
    }
}

struct WateringScheduleDay: Identifiable {
    let date: Date
    let plants: [GardenPlant]

    var id: Date { date }
}
