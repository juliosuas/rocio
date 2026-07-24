import ImageIO
import UIKit

struct IdentificationResult: Identifiable, Equatable, Sendable {
    let id = UUID()
    let flower: Flower
    let identity: PlantIdentity
    let careProfile: PlantCareProfile
    let confidence: Double
    let candidates: [Candidate]
    let isUncertain: Bool
    let provider: IdentificationProvider
    let remainingCloudScans: Int?
    let externalName: String?
    let externalScientificName: String?
    let externalCandidates: [ExternalCandidate]
    let isPlant: Bool?

    struct ExternalCandidate: Identifiable, Equatable, Sendable {
        let id: String
        let sourceID: String?
        let name: String
        let scientificName: String
        let confidence: Double
        let rank: String?
        let nameLocale: String?

        var identity: PlantIdentity {
            PlantIdentity(
                source: .plantID,
                sourceID: sourceID,
                commonName: name,
                scientificName: scientificName,
                rank: rank,
                nameLocale: nameLocale
            ).normalized(fallback: scientificName)
        }
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
        externalCandidates: [ExternalCandidate] = [],
        identity: PlantIdentity? = nil,
        careProfile: PlantCareProfile? = nil,
        isPlant: Bool? = nil
    ) {
        self.flower = flower
        self.identity = identity ?? .bundled(flower)
        self.careProfile = careProfile ?? .bundled(flower)
        self.confidence = confidence
        self.candidates = candidates
        self.isUncertain = isUncertain
        self.provider = provider
        self.remainingCloudScans = remainingCloudScans
        self.externalName = externalName
        self.externalScientificName = externalScientificName
        self.externalCandidates = externalCandidates
        self.isPlant = isPlant
    }

    var displayName: String { externalName ?? flower.name }
    var displayScientificName: String { externalScientificName ?? flower.scientific }
    var usesExternalSuggestion: Bool { externalName != nil }
    var canSaveToGarden: Bool { isPlant != false }
    var alternateExternalCandidates: [ExternalCandidate] {
        externalCandidates.filter { $0.identity != identity }
    }

    struct Candidate: Identifiable, Equatable, Sendable {
        let id: String
        let flower: Flower
        let confidence: Double
    }

    var confidenceBand: IdentificationConfidenceBand {
        IdentificationConfidenceBand(confidence: confidence, isUncertain: isUncertain)
    }
}

struct ScannerImageProcessor {
    static let maximumPixelDimension = 1_600

    func prepare(
        data: Data,
        maximumPixelDimension: Int = Self.maximumPixelDimension
    ) async -> UIImage? {
        guard maximumPixelDimension > 0 else { return nil }
        let task = Task.detached(priority: .userInitiated) {
            autoreleasepool {
                Self.downsampledImage(
                    data: data,
                    maximumPixelDimension: maximumPixelDimension
                ).map(PreparedImage.init)
            }
        }
        return await withTaskCancellationHandler {
            await task.value?.image
        } onCancel: {
            task.cancel()
        }
    }

    func prepare(
        image: UIImage,
        maximumPixelDimension: Int = Self.maximumPixelDimension
    ) async -> UIImage? {
        guard maximumPixelDimension > 0 else { return nil }
        let source = PreparedImage(image)
        let task = Task.detached(priority: .userInitiated) {
            autoreleasepool {
                Self.downsampledImage(
                    image: source.image,
                    maximumPixelDimension: maximumPixelDimension
                ).map(PreparedImage.init)
            }
        }
        return await withTaskCancellationHandler {
            await task.value?.image
        } onCancel: {
            task.cancel()
        }
    }

    static func pixelDimensions(of image: UIImage) -> CGSize {
        if let cgImage = image.cgImage {
            return CGSize(width: cgImage.width, height: cgImage.height)
        }
        return CGSize(
            width: image.size.width * image.scale,
            height: image.size.height * image.scale
        )
    }

    private static func downsampledImage(
        data: Data,
        maximumPixelDimension: Int
    ) -> UIImage? {
        guard !Task.isCancelled,
              let source = CGImageSourceCreateWithData(data as CFData, [
                  kCGImageSourceShouldCache: false,
              ] as CFDictionary) else { return nil }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelDimension,
            kCGImageSourceShouldCacheImmediately: true,
        ] as CFDictionary
        guard !Task.isCancelled,
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else {
            return nil
        }
        return UIImage(cgImage: thumbnail, scale: 1, orientation: .up)
    }

    private static func downsampledImage(
        image: UIImage,
        maximumPixelDimension: Int
    ) -> UIImage? {
        guard !Task.isCancelled, let source = image.cgImage else { return nil }
        let largestDimension = max(source.width, source.height)
        guard largestDimension > maximumPixelDimension else { return image }

        let scale = Double(maximumPixelDimension) / Double(largestDimension)
        let width = max(1, Int((Double(source.width) * scale).rounded()))
        let height = max(1, Int((Double(source.height) * scale).rounded()))
        let bytesPerPixel = 4
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * bytesPerPixel,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard !Task.isCancelled, let thumbnail = context.makeImage() else { return nil }
        return UIImage(
            cgImage: thumbnail,
            scale: 1,
            orientation: image.imageOrientation
        )
    }

    private final class PreparedImage: @unchecked Sendable {
        let image: UIImage

        init(_ image: UIImage) {
            self.image = image
        }
    }
}

enum IdentificationProvider: Equatable, Sendable {
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

enum ScannerAnalysisDestination: Equatable, Sendable {
    case cloud
    case onDevice
}

enum IdentificationConfidenceBand: String, Equatable, Sendable {
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
        guard let cgImage = image.cgImage else { return nil }
        return identify(cgImage: cgImage, catalog: catalog)
    }

    func identify(cgImage: CGImage, catalog: [Flower] = FlowerCatalog.all) -> IdentificationResult? {
        guard !Task.isCancelled, let signature = ImageColorSignature(cgImage: cgImage) else { return nil }
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

struct OnDeviceFlowerIdentifier {
    func identify(image: UIImage) async -> IdentificationResult? {
        guard let cgImage = image.cgImage else { return nil }
        let source = SourceImage(cgImage)
        let task = Task.detached(priority: .userInitiated) {
            FlowerIdentifier().identify(cgImage: source.cgImage)
        }
        return await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private final class SourceImage: @unchecked Sendable {
        let cgImage: CGImage

        init(_ cgImage: CGImage) {
            self.cgImage = cgImage
        }
    }
}

struct HybridFlowerIdentifier {
    private let local = OnDeviceFlowerIdentifier()

    func identifyOnDevice(image: UIImage) async -> IdentificationResult? {
        await local.identify(image: image)
    }

    @MainActor
    func identify(
        image: UIImage,
        destination: ScannerAnalysisDestination,
        sessionStore: SessionStore
    ) async -> IdentificationResult? {
        switch destination {
        case .cloud:
            await identify(image: image, sessionStore: sessionStore)
        case .onDevice:
            await identifyOnDevice(image: image)
        }
    }

    @MainActor
    func identify(image: UIImage, sessionStore: SessionStore) async -> IdentificationResult? {
        let localTask = Task { await local.identify(image: image) }
        defer { localTask.cancel() }
        if sessionStore.isDemoMode {
            return await localTask.value
        }
        do {
            let remote = try await sessionStore.identify(image: image)
            guard let localResult = await localTask.value else { return nil }
            let candidates = matchedCandidates(remote.suggestions)
            let external = externalCandidates(remote.suggestions, locale: remote.locale)
            if let top = external.first {
                let exactGuide = exactCatalogMatch(for: top.scientificName)
                let closestGuide = exactGuide ?? candidates.first?.flower ?? localResult.flower
                let candidateConfidence = top.confidence
                var careProfile = exactGuide.map(PlantCareProfile.bundled)
                    ?? PlantCareProfile(source: .plantID)
                careProfile.fetchedAt = Date()
                return IdentificationResult(
                    flower: closestGuide,
                    confidence: candidateConfidence,
                    candidates: candidates.isEmpty ? localResult.candidates : Array(candidates.prefix(3)),
                    isUncertain: candidateConfidence < 64 || remote.isPlant?.binary == false,
                    provider: .cloud,
                    remainingCloudScans: remote.remaining,
                    externalName: top.name,
                    externalScientificName: top.scientificName,
                    externalCandidates: external,
                    identity: top.identity,
                    careProfile: careProfile,
                    isPlant: remote.isPlant?.binary
                )
            }

            guard let best = candidates.first else {
                return IdentificationResult(
                    flower: localResult.flower,
                    confidence: localResult.confidence,
                    candidates: localResult.candidates,
                    isUncertain: localResult.isUncertain,
                    provider: .cloud,
                    remainingCloudScans: remote.remaining,
                    isPlant: remote.isPlant?.binary
                )
            }
            return IdentificationResult(
                flower: best.flower,
                confidence: best.confidence,
                candidates: Array(candidates.prefix(3)),
                isUncertain: best.confidence < 64 || best.confidence - (candidates.dropFirst().first?.confidence ?? 0) < 8,
                provider: .cloud,
                remainingCloudScans: remote.remaining,
                externalCandidates: external,
                isPlant: remote.isPlant?.binary
            )
        } catch {
            let localResult = await localTask.value
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

    private func externalCandidates(
        _ suggestions: [RemoteIdentificationResponse.Suggestion],
        locale: String?
    ) -> [IdentificationResult.ExternalCandidate] {
        suggestions.prefix(3).compactMap { suggestion in
            let commonName = (suggestion.commonNames.first ?? suggestion.name)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let scientificName = suggestion.scientificName
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !commonName.isEmpty || !scientificName.isEmpty else { return nil }
            let displayName = commonName.isEmpty ? scientificName : commonName
            let stableID = suggestion.id?.isEmpty == false
                ? suggestion.id!
                : "\(scientificName)|\(displayName)"
            return IdentificationResult.ExternalCandidate(
                id: stableID,
                sourceID: suggestion.id,
                name: displayName,
                scientificName: scientificName.isEmpty ? displayName : scientificName,
                confidence: min(99, max(1, suggestion.probability * 100)),
                rank: suggestion.rank,
                nameLocale: locale
            )
        }
    }

    private func exactCatalogMatch(for scientificName: String) -> Flower? {
        let target = normalize(scientificName)
        guard !target.isEmpty else { return nil }
        return FlowerCatalog.all.first { normalize($0.scientific) == target }
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

    init?(cgImage: CGImage) {
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

            let (h, s, v) = Self.hsv(red: Double(r), green: Double(g), blue: Double(b))

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

    private static func hsv(red: Double, green: Double, blue: Double) -> (Double, Double, Double) {
        let maximum = max(red, max(green, blue))
        let minimum = min(red, min(green, blue))
        let delta = maximum - minimum
        let saturation = maximum == 0 ? 0 : delta / maximum
        guard delta > 0 else { return (0, saturation, maximum) }

        let hue: Double
        if maximum == red {
            hue = 60 * ((green - blue) / delta).truncatingRemainder(dividingBy: 6)
        } else if maximum == green {
            hue = 60 * (((blue - red) / delta) + 2)
        } else {
            hue = 60 * (((red - green) / delta) + 4)
        }
        return (hue < 0 ? hue + 360 : hue, saturation, maximum)
    }
}
