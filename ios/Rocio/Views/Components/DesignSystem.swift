import SwiftUI

extension Color {
    static let rocioLeaf = Color(red: 0.42, green: 0.58, blue: 0.30)
    static let rocioLeafSoft = Color(red: 0.88, green: 0.94, blue: 0.84)
    static let rocioRose = Color(red: 0.88, green: 0.48, blue: 0.62)
    static let rocioSoil = Color(red: 0.43, green: 0.34, blue: 0.24)
    static let rocioCanvas = Color(red: 0.98, green: 0.97, blue: 0.93)
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

