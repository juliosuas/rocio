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
        case .healthy: "Saludable"
        case .needsWater: "Necesita agua"
        case .needsSun: "Necesita sol"
        case .sick: "Enferma"
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
        case .good: "Al dia"
        case .soon: "Pronto"
        case .overdue: "Toca regar"
        }
    }
}

