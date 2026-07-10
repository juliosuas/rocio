import SwiftUI
import UIKit

extension Color {
    static let rocioLeaf = Color(red: 0.33, green: 0.51, blue: 0.29)
    static let rocioLeafDeep = adaptive(light: .init(red: 0.10, green: 0.30, blue: 0.23, alpha: 1), dark: .init(red: 0.65, green: 0.82, blue: 0.60, alpha: 1))
    static let rocioLeafAction = Color(red: 0.10, green: 0.30, blue: 0.23)
    static let rocioLeafSoft = adaptive(light: .init(red: 0.89, green: 0.94, blue: 0.87, alpha: 1), dark: .init(red: 0.12, green: 0.22, blue: 0.16, alpha: 1))
    static let rocioRose = Color(red: 0.78, green: 0.29, blue: 0.45)
    static let rocioRoseSoft = adaptive(light: .init(red: 0.98, green: 0.89, blue: 0.91, alpha: 1), dark: .init(red: 0.24, green: 0.12, blue: 0.16, alpha: 1))
    static let rocioTeal = Color(red: 0.12, green: 0.48, blue: 0.49)
    static let rocioTealSoft = adaptive(light: .init(red: 0.86, green: 0.94, blue: 0.94, alpha: 1), dark: .init(red: 0.10, green: 0.22, blue: 0.22, alpha: 1))
    static let rocioSoil = adaptive(light: .init(red: 0.20, green: 0.18, blue: 0.15, alpha: 1), dark: .init(red: 0.94, green: 0.93, blue: 0.89, alpha: 1))
    static let rocioCanvas = adaptive(light: .init(red: 0.98, green: 0.98, blue: 0.96, alpha: 1), dark: .init(red: 0.06, green: 0.07, blue: 0.06, alpha: 1))
    static let rocioSurface = adaptive(light: .white, dark: .init(red: 0.12, green: 0.13, blue: 0.12, alpha: 1))
    static let rocioLine = adaptive(light: .black.withAlphaComponent(0.10), dark: .white.withAlphaComponent(0.14))
    static let rocioAmber = adaptive(light: .init(red: 0.67, green: 0.38, blue: 0.04, alpha: 1), dark: .init(red: 0.96, green: 0.68, blue: 0.30, alpha: 1))

    private static func adaptive(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }
}

extension Font {
    static let rocioDisplay = Font.system(size: 34, weight: .semibold, design: .serif)
    static let rocioTitle = Font.system(size: 24, weight: .semibold, design: .serif)
}

struct RocioCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.rocioSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.rocioLine)
            )
    }
}

struct MetricPill: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.bold())
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.rocioLine)
        )
    }
}

struct PillLabel: View {
    let title: String
    let systemImage: String
    var tint: Color = .rocioLeafDeep

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint.opacity(0.11), in: Capsule())
            .foregroundStyle(tint)
            .lineLimit(1)
    }
}

struct RocioSectionHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.rocioTitle)
                .foregroundStyle(Color.rocioSoil)
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct RocioFilterChip: View {
    let title: String
    let systemImage: String
    let isSelected: Bool

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 12)
            .frame(height: 44)
            .foregroundStyle(isSelected ? Color.white : Color.rocioSoil)
            .background(isSelected ? Color.rocioLeafAction : Color.rocioSurface, in: Capsule())
            .overlay {
                if !isSelected {
                    Capsule().stroke(Color.rocioLine)
                }
            }
    }
}

struct RocioStatusBadge: View {
    let title: String
    let systemImage: String
    var tint: Color

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.bold))
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .foregroundStyle(tint)
            .background(tint.opacity(0.12), in: Capsule())
    }
}

struct RocioPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .padding(.horizontal, 16)
            .frame(minHeight: 46)
            .frame(maxWidth: .infinity)
            .background(Color.rocioLeafAction, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .foregroundStyle(.white)
            .opacity(configuration.isPressed ? 0.78 : 1)
    }
}

struct RocioSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .padding(.horizontal, 16)
            .frame(minHeight: 46)
            .frame(maxWidth: .infinity)
            .background(Color.rocioSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .foregroundStyle(Color.rocioLeafDeep)
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.rocioLine))
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}
