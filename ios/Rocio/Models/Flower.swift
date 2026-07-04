import Foundation

struct Flower: Identifiable, Codable, Equatable {
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

    var sunlightLabel: String { sunlight.label }
    var difficultyLabel: String {
        switch difficulty {
        case 1: "Facil"
        case 2: "Media"
        default: "Avanzada"
        }
    }
}

enum Sunlight: String, Codable, CaseIterable {
    case fullSun
    case partial
    case shade

    var label: String {
        switch self {
        case .fullSun: "Sol pleno"
        case .partial: "Luz parcial"
        case .shade: "Sombra"
        }
    }
}

enum ToxicLevel: String, Codable {
    case safe
    case caution
    case toxic

    var label: String {
        switch self {
        case .safe: "Segura"
        case .caution: "Precaucion"
        case .toxic: "Toxica"
        }
    }
}

struct FlowerColorProfile: Codable, Equatable {
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

