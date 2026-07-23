import Foundation

@MainActor
final class GardenStore: ObservableObject {
    @Published private(set) var plants: [GardenPlant]
    @Published private(set) var isDemoMode = false
    @Published private(set) var persistenceStatus: GardenPersistence.LoadStatus
    @Published private(set) var mutationErrorMessage: String?
    /// Returns `true` only after an authenticated cloud mutation has been
    /// durably accepted by the pending journal. Local-only and demo stores can
    /// accept changes without installing a handler.
    var cloudChangeHandler: ((GardenChange) -> Bool)?
    private var plantsBeforeDemo: [GardenPlant]?

    var canAcceptLocalChanges: Bool {
        isDemoMode || persistenceStatus != .unrecoverableCorruption
    }

    init(plants: [GardenPlant]? = nil) {
        if let plants {
            self.plants = plants
            persistenceStatus = .loaded
        } else {
            let result = GardenPersistence.loadSnapshot()
            self.plants = result.plants
            persistenceStatus = result.status
        }
    }

    @discardableResult
    func add(_ flower: Flower) -> Bool {
        guard canAcceptLocalChanges else { return false }
        let plant = GardenPlant(flowerId: flower.id, nickname: flower.name)
        return add(plant)
    }

    @discardableResult
    func add(_ plant: GardenPlant) -> Bool {
        guard canAcceptLocalChanges else { return false }
        guard !plants.contains(where: { $0.id == plant.id }) else { return false }
        let normalizedPlant = plant.normalizingTextFields()
        guard acceptsCloudChange(.create(normalizedPlant)) else { return false }
        plants.append(normalizedPlant)
        persist()
        return true
    }

    @discardableResult
    func add(
        identity: PlantIdentity,
        careProfile: PlantCareProfile,
        nickname: String? = nil,
        at date: Date = Date()
    ) -> GardenPlant? {
        guard canAcceptLocalChanges else { return nil }
        let plant = GardenPlant(
            identity: identity,
            careProfile: careProfile,
            nickname: nickname,
            addedAt: date,
            lastWateredAt: date,
            updatedAt: date
        ).normalizingTextFields()
        guard acceptsCloudChange(.create(plant)) else { return nil }
        plants.append(plant)
        persist()
        return plant
    }

    @discardableResult
    func water(_ plant: GardenPlant, at date: Date = Date()) -> Bool {
        guard canAcceptLocalChanges else { return false }
        guard let index = plants.firstIndex(where: { $0.id == plant.id }) else { return false }
        var updatedPlant = plants[index]
        updatedPlant.lastWateredAt = date
        updatedPlant.updatedAt = date
        if updatedPlant.status == .needsWater {
            updatedPlant.status = .healthy
        }
        guard acceptsCloudChange(.upsert(updatedPlant)) else { return false }
        plants[index] = updatedPlant
        persist()
        return true
    }

    @discardableResult
    func update(
        _ plant: GardenPlant,
        nickname: String,
        status: PlantStatus,
        notes: String,
        careProfile: PlantCareProfile? = nil
    ) -> Bool {
        guard canAcceptLocalChanges else { return false }
        guard let index = plants.firstIndex(where: { $0.id == plant.id }) else { return false }
        let previousNickname = plants[index].nickname
        var updatedPlant = plants[index]
        updatedPlant.nickname = nickname
        updatedPlant.status = status
        updatedPlant.notes = notes
        if let careProfile {
            updatedPlant.careProfile = careProfile
        }
        updatedPlant.updatedAt = Date()
        updatedPlant = updatedPlant.normalizingTextFields(nicknameFallback: previousNickname)
        guard acceptsCloudChange(.upsert(updatedPlant)) else { return false }
        plants[index] = updatedPlant
        persist()
        return true
    }

    @discardableResult
    func delete(_ plant: GardenPlant, at date: Date = Date()) -> Bool {
        guard canAcceptLocalChanges else { return false }
        guard plants.contains(where: { $0.id == plant.id }) else { return false }
        guard acceptsCloudChange(.delete(plant.id, at: date)) else { return false }
        plants.removeAll { $0.id == plant.id }
        persist()
        return true
    }

    @discardableResult
    func reset(at date: Date = Date()) -> Bool {
        // Reset is the explicit recovery path for an unreadable local
        // snapshot, so it remains available even when ordinary edits are
        // blocked. An authenticated reset still has to enter the durable
        // cloud journal before local data is cleared.
        guard acceptsCloudChange(.reset(at: date)) else { return false }
        plants.removeAll()
        if !isDemoMode {
            GardenPersistence.clearPlants()
            persistenceStatus = .empty
        }
        return true
    }

    func clearLocalCache() {
        plants.removeAll()
        GardenPersistence.clearPlants()
        persistenceStatus = .empty
    }

    func reloadFromPersistence() {
        guard !isDemoMode else { return }
        let result = GardenPersistence.loadSnapshot()
        persistenceStatus = result.status
        guard result.status != .unrecoverableCorruption else { return }
        guard result.plants != plants else { return }
        plants = result.plants
    }

    func replaceFromCloud(_ cloudPlants: [GardenPlant]) {
        let normalizedPlants = cloudPlants
            .map { $0.normalizingTextFields() }
            .sorted { $0.addedAt < $1.addedAt }
        guard normalizedPlants != plants || persistenceStatus == .unrecoverableCorruption else { return }
        plants = normalizedPlants
        persist(allowsCorruptionRecovery: true)
    }

    func flower(for plant: GardenPlant) -> Flower? {
        guard let flowerID = plant.flowerId else { return nil }
        return FlowerCatalog.flower(id: flowerID)
    }

    private func acceptsCloudChange(_ change: GardenChange) -> Bool {
        guard !isDemoMode else { return true }
        let accepted = cloudChangeHandler?(change) ?? true
        mutationErrorMessage = accepted
            ? nil
            : L10n.text(
                "garden.change.rejected",
                fallback: "Your change was not saved because Rocio could not safely update its cloud queue. Your garden is unchanged; retry after sync recovers."
            )
        return accepted
    }

    func clearMutationError() {
        mutationErrorMessage = nil
    }

    func wateringIntervalDays(for plant: GardenPlant) -> Int? {
        plant.resolvedWateringIntervalDays
    }

    func urgency(for plant: GardenPlant, now: Date = Date()) -> WateringUrgency? {
        guard let wateringIntervalDays = wateringIntervalDays(for: plant) else { return nil }
        let days = Calendar.current.dateComponents([.day], from: plant.lastWateredAt, to: now).day ?? 0
        if days >= wateringIntervalDays { return .overdue }
        if days >= max(0, wateringIntervalDays - 1) { return .soon }
        return .good
    }

    func nextWateringDate(for plant: GardenPlant, calendar: Calendar = .current) -> Date? {
        guard let days = wateringIntervalDays(for: plant) else { return nil }
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
        let scheduledPlants = plants.compactMap { plant -> (plant: GardenPlant, dueDate: Date)? in
            guard let dueDate = nextWateringDate(for: plant, calendar: calendar) else { return nil }
            return (plant: plant, dueDate: dueDate)
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
        var unscheduled = 0
        var nextDate: Date?

        for plant in plants {
            switch urgency(for: plant, now: now) {
            case .some(.overdue):
                overdue += 1
            case .some(.soon):
                soon += 1
            case .some(.good):
                break
            case .none:
                unscheduled += 1
            }

            if let candidate = nextWateringDate(for: plant) {
                if let currentNextDate = nextDate {
                    if candidate < currentNextDate {
                        nextDate = candidate
                    }
                } else {
                    nextDate = candidate
                }
            }
        }

        return GardenSummary(
            plantCount: plants.count,
            overdueCount: overdue,
            soonCount: soon,
            unscheduledCount: unscheduled,
            nextWateringDate: nextDate
        )
    }

    private func persist(allowsCorruptionRecovery: Bool = false) {
        guard !isDemoMode else { return }
        guard allowsCorruptionRecovery || persistenceStatus != .unrecoverableCorruption else { return }
        if GardenPersistence.savePlants(
            plants,
            allowsCorruptionRecovery: allowsCorruptionRecovery
        ) {
            persistenceStatus = .loaded
        }
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
        if let plantsBeforeDemo {
            plants = plantsBeforeDemo
        } else {
            let result = GardenPersistence.loadSnapshot()
            plants = result.plants
            persistenceStatus = result.status
        }
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
    let unscheduledCount: Int
    let nextWateringDate: Date?

    var needsAttentionCount: Int {
        overdueCount + soonCount + unscheduledCount
    }

    var statusLabel: String {
        if plantCount == 0 { return L10n.text("garden.summary.empty", fallback: "No plants yet") }
        if overdueCount > 0 { return L10n.text("garden.summary.overdue", fallback: "Time to water") }
        if soonCount > 0 { return L10n.text("garden.summary.soon", fallback: "Check soon") }
        if unscheduledCount > 0 {
            return L10n.text("garden.summary.unscheduled", fallback: "Set care schedule")
        }
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
