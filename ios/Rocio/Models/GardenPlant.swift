import Foundation

struct GardenPlant: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var flowerId: String
    var nickname: String
    var addedAt: Date
    var lastWateredAt: Date
    var status: PlantStatus
    var notes: String

    init(
        id: UUID = UUID(),
        flowerId: String,
        nickname: String,
        addedAt: Date = Date(),
        lastWateredAt: Date = Date(),
        status: PlantStatus = .healthy,
        notes: String = ""
    ) {
        self.id = id
        self.flowerId = flowerId
        self.nickname = nickname
        self.addedAt = addedAt
        self.lastWateredAt = lastWateredAt
        self.status = status
        self.notes = notes
    }
}

enum PlantStatus: String, Codable, CaseIterable, Identifiable {
    case healthy
    case needsWater
    case needsSun
    case sick

    var id: String { rawValue }

    var label: String {
        switch self {
        case .healthy: L10n.text("plant.status.healthy", fallback: "Healthy")
        case .needsWater: L10n.text("plant.status.water", fallback: "Needs water")
        case .needsSun: L10n.text("plant.status.sun", fallback: "Needs sun")
        case .sick: L10n.text("plant.status.sick", fallback: "Unwell")
        }
    }

    var systemImage: String {
        switch self {
        case .healthy: "checkmark.seal"
        case .needsWater: "drop"
        case .needsSun: "sun.max"
        case .sick: "cross.case"
        }
    }
}

enum WateringUrgency: String {
    case good
    case soon
    case overdue

    var label: String {
        switch self {
        case .good: L10n.text("watering.good", fallback: "On track")
        case .soon: L10n.text("watering.soon", fallback: "Soon")
        case .overdue: L10n.text("watering.overdue", fallback: "Water now")
        }
    }
}
