import SwiftUI
import UIKit

struct FlowerImage: View {
    let flower: Flower
    var size: CGFloat = 72

    var body: some View {
        ZStack {
            if let image = UIImage(named: flower.imageName) {
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
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityLabel(flower.name)
    }
}

