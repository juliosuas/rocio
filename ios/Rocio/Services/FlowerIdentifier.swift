import UIKit

struct IdentificationResult: Identifiable, Equatable {
    let id = UUID()
    let flower: Flower
    let confidence: Double
    let candidates: [Candidate]
    let isUncertain: Bool
    let provider: IdentificationProvider
    let remainingCloudScans: Int?
    let externalName: String?
    let externalScientificName: String?
    let externalCandidates: [ExternalCandidate]

    struct ExternalCandidate: Identifiable, Equatable {
        let id: String
        let name: String
        let scientificName: String
        let confidence: Double
    }

    init(
        flower: Flower,
        confidence: Double,
        candidates: [Candidate],
        isUncertain: Bool,
        provider: IdentificationProvider = .onDevice,
        remainingCloudScans: Int? = nil,
        externalName: String? = nil,
        externalScientificName: String? = nil,
        externalCandidates: [ExternalCandidate] = []
    ) {
        self.flower = flower
        self.confidence = confidence
        self.candidates = candidates
        self.isUncertain = isUncertain
        self.provider = provider
        self.remainingCloudScans = remainingCloudScans
        self.externalName = externalName
        self.externalScientificName = externalScientificName
        self.externalCandidates = externalCandidates
    }

    var displayName: String { externalName ?? flower.name }
    var displayScientificName: String { externalScientificName ?? flower.scientific }
    var usesExternalSuggestion: Bool { externalName != nil }

    struct Candidate: Identifiable, Equatable {
        let id: String
        let flower: Flower
        let confidence: Double
    }

    var confidenceBand: IdentificationConfidenceBand {
        IdentificationConfidenceBand(confidence: confidence, isUncertain: isUncertain)
    }
}

enum IdentificationProvider: Equatable {
    case cloud
    case onDevice
    case onDeviceFallback

    var label: String {
        switch self {
        case .cloud: L10n.text("scanner.provider.cloud", fallback: "AI cloud match")
        case .onDevice: L10n.text("scanner.provider.local", fallback: "On-device match")
        case .onDeviceFallback: L10n.text("scanner.provider.fallback", fallback: "On-device fallback")
        }
    }
}

enum IdentificationConfidenceBand: String, Equatable {
    case experimental
    case possible
    case probable

    init(confidence: Double, isUncertain: Bool) {
        if isUncertain || confidence < 64 {
            self = .experimental
        } else if confidence < 82 {
            self = .possible
        } else {
            self = .probable
        }
    }

    var label: String {
        switch self {
        case .experimental: L10n.text("scanner.confidence.experimental", fallback: "Experimental")
        case .possible: L10n.text("scanner.confidence.possible", fallback: "Possible")
        case .probable: L10n.text("scanner.confidence.probable", fallback: "Probable")
        }
    }

    var reviewSafeCopy: String {
        switch self {
        case .experimental:
            L10n.text("scanner.confidence.experimental.copy", fallback: "Use this as a clue, not a diagnosis.")
        case .possible:
            L10n.text("scanner.confidence.possible.copy", fallback: "Compare candidates before acting.")
        case .probable:
            L10n.text("scanner.confidence.probable.copy", fallback: "Visible traits match; verify the care guide.")
        }
    }
}

struct FlowerIdentifier {
    func identify(image: UIImage, catalog: [Flower] = FlowerCatalog.all) -> IdentificationResult? {
        guard let signature = ImageColorSignature(image: image) else { return nil }
        let ranked = catalog.map { flower -> IdentificationResult.Candidate in
            let score = score(signature, against: flower.colorProfile)
            return .init(id: flower.id, flower: flower, confidence: min(96, max(15, score * 100)))
        }
        .sorted { $0.confidence > $1.confidence }

        guard let best = ranked.first else { return nil }
        let second = ranked.dropFirst().first?.confidence ?? 0
        let separation = best.confidence - second
        return IdentificationResult(
            flower: best.flower,
            confidence: best.confidence,
            candidates: Array(ranked.prefix(3)),
            isUncertain: best.confidence < 64 || separation < 8
        )
    }

    private func score(_ signature: ImageColorSignature, against profile: FlowerColorProfile) -> Double {
        let hueScore = signature.hues.reduce(0.0) { partial, hue in
            partial + (profile.hueRanges.contains(where: { $0.contains(hue) }) ? 1.0 : 0.0)
        } / Double(max(1, signature.hues.count))

        let saturationScore = profile.saturation.contains(signature.averageSaturation) ? 1.0 : 0.35
        let brightnessScore = profile.brightness.contains(signature.averageBrightness) ? 1.0 : 0.35

        let affinity =
            signature.whiteRatio * profile.whiteAffinity +
            signature.greenRatio * profile.greenAffinity +
            signature.yellowRatio * profile.yellowAffinity +
            signature.orangeRatio * profile.orangeAffinity +
            signature.redRatio * profile.redAffinity +
            signature.purpleRatio * profile.purpleAffinity +
            signature.blueRatio * profile.blueAffinity

        return min(0.96, max(0.05, hueScore * 0.45 + saturationScore * 0.12 + brightnessScore * 0.12 + affinity * 0.18))
    }
}

@MainActor
struct HybridFlowerIdentifier {
    private let local = FlowerIdentifier()

    func identify(image: UIImage, sessionStore: SessionStore) async -> IdentificationResult? {
        let localResult = local.identify(image: image)
        do {
            let remote = try await sessionStore.identify(image: image)
            let candidates = matchedCandidates(remote.suggestions)
            guard let best = candidates.first else {
                guard let result = localResult, let top = remote.suggestions.first else { return localResult }
                return IdentificationResult(
                    flower: result.flower,
                    confidence: min(99, max(1, top.probability * 100)),
                    candidates: result.candidates,
                    isUncertain: top.probability < 0.64,
                    provider: .cloud,
                    remainingCloudScans: remote.remaining,
                    externalName: top.commonNames.first ?? top.name,
                    externalScientificName: top.scientificName,
                    externalCandidates: remote.suggestions.prefix(3).map { suggestion in
                        IdentificationResult.ExternalCandidate(
                            id: "\(suggestion.scientificName)-\(suggestion.name)",
                            name: suggestion.commonNames.first ?? suggestion.name,
                            scientificName: suggestion.scientificName,
                            confidence: min(99, max(1, suggestion.probability * 100))
                        )
                    }
                )
            }
            return IdentificationResult(
                flower: best.flower,
                confidence: best.confidence,
                candidates: Array(candidates.prefix(3)),
                isUncertain: best.confidence < 64 || best.confidence - (candidates.dropFirst().first?.confidence ?? 0) < 8,
                provider: .cloud,
                remainingCloudScans: remote.remaining,
                externalCandidates: remote.suggestions.prefix(3).map { suggestion in
                    IdentificationResult.ExternalCandidate(
                        id: "\(suggestion.scientificName)-\(suggestion.name)",
                        name: suggestion.commonNames.first ?? suggestion.name,
                        scientificName: suggestion.scientificName,
                        confidence: min(99, max(1, suggestion.probability * 100))
                    )
                }
            )
        } catch {
            return localResult.map { result in
                IdentificationResult(
                    flower: result.flower,
                    confidence: result.confidence,
                    candidates: result.candidates,
                    isUncertain: result.isUncertain,
                    provider: .onDeviceFallback
                )
            }
        }
    }

    private func matchedCandidates(_ suggestions: [RemoteIdentificationResponse.Suggestion]) -> [IdentificationResult.Candidate] {
        var bestByFlower: [String: IdentificationResult.Candidate] = [:]
        for suggestion in suggestions {
            let terms = [suggestion.name, suggestion.scientificName] + suggestion.commonNames + suggestion.synonyms
            guard let flower = FlowerCatalog.all.first(where: { flower in
                terms.contains { term in
                    let lhs = normalize(term)
                    let names = [normalize(flower.name), normalize(flower.scientific), normalize(flower.id)]
                    let genus = normalize(flower.scientific).split(separator: " ").first.map(String.init) ?? ""
                    return names.contains(lhs) || (!genus.isEmpty && lhs.split(separator: " ").first.map(String.init) == genus)
                }
            }) else { continue }
            let candidate = IdentificationResult.Candidate(
                id: flower.id,
                flower: flower,
                confidence: min(99, max(1, suggestion.probability * 100))
            )
            if candidate.confidence > (bestByFlower[flower.id]?.confidence ?? 0) {
                bestByFlower[flower.id] = candidate
            }
        }
        return bestByFlower.values.sorted { $0.confidence > $1.confidence }
    }

    private func normalize(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct ImageColorSignature {
    let hues: [Double]
    let averageSaturation: Double
    let averageBrightness: Double
    let whiteRatio: Double
    let greenRatio: Double
    let yellowRatio: Double
    let orangeRatio: Double
    let redRatio: Double
    let purpleRatio: Double
    let blueRatio: Double

    init?(image: UIImage) {
        guard let cgImage = image.cgImage else { return nil }
        let size = 72
        let bytesPerPixel = 4
        let bytesPerRow = size * bytesPerPixel
        var rawData = [UInt8](repeating: 0, count: size * size * bytesPerPixel)
        guard let context = CGContext(
            data: &rawData,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: size, height: size))

        var hues: [Double] = []
        var satTotal = 0.0
        var brightTotal = 0.0
        var count = 0.0
        var white = 0.0
        var green = 0.0
        var yellow = 0.0
        var orange = 0.0
        var red = 0.0
        var purple = 0.0
        var blue = 0.0

        for offset in stride(from: 0, to: rawData.count, by: bytesPerPixel * 5) {
            let r = CGFloat(rawData[offset]) / 255.0
            let g = CGFloat(rawData[offset + 1]) / 255.0
            let b = CGFloat(rawData[offset + 2]) / 255.0

            var hue: CGFloat = 0
            var saturation: CGFloat = 0
            var brightness: CGFloat = 0
            UIColor(red: r, green: g, blue: b, alpha: 1).getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: nil)

            let h = Double(hue * 360)
            let s = Double(saturation)
            let v = Double(brightness)

            satTotal += s
            brightTotal += v
            count += 1

            if s < 0.18 && v > 0.72 {
                white += 1
            } else if h >= 70 && h <= 170 {
                green += 1
            } else if h >= 45 && h < 70 {
                yellow += 1
                hues.append(h)
            } else if h >= 18 && h < 45 {
                orange += 1
                hues.append(h)
            } else if h < 18 || h >= 335 {
                red += 1
                hues.append(h)
            } else if h >= 250 && h < 335 {
                purple += 1
                hues.append(h)
            } else if h >= 180 && h < 250 {
                blue += 1
                hues.append(h)
            } else if s > 0.18 {
                hues.append(h)
            }
        }

        let denom = max(1, count)
        self.hues = hues
        self.averageSaturation = satTotal / denom
        self.averageBrightness = brightTotal / denom
        self.whiteRatio = white / denom
        self.greenRatio = green / denom
        self.yellowRatio = yellow / denom
        self.orangeRatio = orange / denom
        self.redRatio = red / denom
        self.purpleRatio = purple / denom
        self.blueRatio = blue / denom
    }
}
