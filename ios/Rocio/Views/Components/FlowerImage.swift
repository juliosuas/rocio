import SwiftUI
import UIKit

struct FlowerImage: View {
    let flower: Flower
    var size: CGFloat = 72
    var cornerRadius: CGFloat = 8

    var body: some View {
        ZStack {
            if let image = bundledFlowerImage(named: flower.imageName) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Text(flower.emoji)
                    .font(.system(size: size * 0.46))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.rocioLeafSoft)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .accessibilityLabel(flower.name)
    }
}

struct FlowerArtwork: View {
    let flower: Flower
    var height: CGFloat = 220
    var cornerRadius: CGFloat = 0

    var body: some View {
        Group {
            if let image = bundledFlowerImage(named: flower.imageName) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Color.rocioLeafSoft
                    Text(flower.emoji).font(.system(size: 72))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .accessibilityLabel(flower.name)
    }
}

private func bundledFlowerImage(named name: String) -> UIImage? {
    UIImage(named: name) ?? UIImage(named: "\(name).jpg")
}
