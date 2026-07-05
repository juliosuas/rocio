import SwiftUI

extension Color {
    static let rocioLeaf = Color(red: 0.42, green: 0.58, blue: 0.30)
    static let rocioLeafDeep = Color(red: 0.18, green: 0.42, blue: 0.31)
    static let rocioLeafSoft = Color(red: 0.88, green: 0.94, blue: 0.84)
    static let rocioRose = Color(red: 0.88, green: 0.48, blue: 0.62)
    static let rocioRoseSoft = Color(red: 0.99, green: 0.88, blue: 0.91)
    static let rocioSoil = Color(red: 0.43, green: 0.34, blue: 0.24)
    static let rocioCanvas = Color(red: 0.98, green: 0.97, blue: 0.93)
    static let rocioLine = Color.black.opacity(0.08)
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
            .background(Color.rocioCanvas, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.rocioLeafSoft, in: Capsule())
            .foregroundStyle(Color.rocioSoil)
    }
}

struct RocioPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .padding(.horizontal, 16)
            .frame(minHeight: 46)
            .frame(maxWidth: .infinity)
            .background(Color.rocioLeafDeep, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .foregroundStyle(.white)
            .opacity(configuration.isPressed ? 0.78 : 1)
    }
}
