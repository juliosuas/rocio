import UIKit

struct IdentificationResult: Identifiable, Equatable {
    let id = UUID()
    let flower: Flower
    let confidence: Double
    let candidates: [Candidate]
    let isUncertain: Bool

    struct Candidate: Identifiable, Equatable {
        let id: String
        let flower: Flower
        let confidence: Double
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

