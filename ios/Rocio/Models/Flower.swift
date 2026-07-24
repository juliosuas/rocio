import Foundation

struct Flower: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let emoji: String
    let imageName: String
    let name: String
    let scientific: String
    let difficulty: Int
    let sunlight: Sunlight
    let waterDays: Int
    let waterMl: Int
    let tempRange: ClosedRange<Int>
    let soil: String
    let seasonLabel: String
    let fact: String
    let toxic: String
    let toxicLevel: ToxicLevel
    let fertilizer: String
    let pruning: String
    let propagation: String
    let companions: String
    let plantingSteps: [String]
    let colorProfile: FlowerColorProfile

    init(
        id: String,
        emoji: String,
        imageName: String,
        name: String,
        scientific: String,
        difficulty: Int,
        sunlight: Sunlight,
        waterDays: Int,
        waterMl: Int,
        tempRange: ClosedRange<Int>,
        soil: String,
        seasonLabel: String,
        fact: String,
        toxic: String,
        toxicLevel: ToxicLevel,
        fertilizer: String,
        pruning: String,
        propagation: String,
        companions: String,
        plantingSteps: [String],
        colorProfile: FlowerColorProfile
    ) {
        self.id = id
        self.emoji = emoji
        self.imageName = imageName
        self.name = L10n.text("flower.\(id).name", fallback: name)
        self.scientific = scientific
        self.difficulty = difficulty
        self.sunlight = sunlight
        self.waterDays = waterDays
        self.waterMl = waterMl
        self.tempRange = tempRange
        self.soil = L10n.text("flower.\(id).soil", fallback: soil)
        self.seasonLabel = L10n.text("flower.\(id).season", fallback: seasonLabel)
        self.fact = L10n.text("flower.\(id).fact", fallback: fact)
        self.toxic = L10n.text("flower.\(id).toxicity", fallback: toxic)
        self.toxicLevel = toxicLevel
        self.fertilizer = L10n.text("flower.\(id).fertilizer", fallback: fertilizer)
        self.pruning = L10n.text("flower.\(id).pruning", fallback: pruning)
        self.propagation = L10n.text("flower.\(id).propagation", fallback: propagation)
        self.companions = L10n.text("flower.\(id).companions", fallback: companions)
        self.plantingSteps = plantingSteps.enumerated().map { index, step in
            L10n.text("flower.\(id).planting.\(index + 1)", fallback: step)
        }
        self.colorProfile = colorProfile
    }

    var sunlightLabel: String { sunlight.label }
    var difficultyLabel: String {
        switch difficulty {
        case 1: L10n.text("difficulty.easy", fallback: "Easy")
        case 2: L10n.text("difficulty.medium", fallback: "Medium")
        default: L10n.text("difficulty.advanced", fallback: "Advanced")
        }
    }
}

enum Sunlight: String, Codable, CaseIterable, Sendable {
    case fullSun
    case partial
    case shade

    var label: String {
        switch self {
        case .fullSun: L10n.text("sunlight.full", fallback: "Full sun")
        case .partial: L10n.text("sunlight.partial", fallback: "Partial light")
        case .shade: L10n.text("sunlight.shade", fallback: "Shade")
        }
    }
}

enum ToxicLevel: String, Codable, Sendable {
    case safe
    case caution
    case toxic

    var label: String {
        switch self {
        case .safe: L10n.text("toxicity.safe", fallback: "Safe")
        case .caution: L10n.text("toxicity.caution", fallback: "Caution")
        case .toxic: L10n.text("toxicity.toxic", fallback: "Toxic")
        }
    }
}

struct FlowerColorProfile: Codable, Equatable, Sendable {
    let hueRanges: [ClosedRange<Double>]
    let saturation: ClosedRange<Double>
    let brightness: ClosedRange<Double>
    let whiteAffinity: Double
    let greenAffinity: Double
    let yellowAffinity: Double
    let orangeAffinity: Double
    let redAffinity: Double
    let purpleAffinity: Double
    let blueAffinity: Double
}
