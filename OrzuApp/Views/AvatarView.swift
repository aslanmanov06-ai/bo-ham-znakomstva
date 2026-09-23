import SwiftUI
import UIKit

/// Аватар по avatarUrl с сервера (нужен токен, поэтому не AsyncImage) или первая буква имени.
struct AvatarView: View {
    let avatarUrl: String?
    let name: String
    var size: CGFloat = 44

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Circle()
                    .fill(placeholderGradient)
                    .overlay(
                        Text(String(name.prefix(1)).uppercased())
                            .font(.display(size: size * 0.36, weight: .semibold))
                            .foregroundStyle(.white)
                    )
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .task(id: avatarUrl) {
            guard let avatarUrl else {
                image = nil
                return
            }
            // Не загрузился — остаётся буква; повторим при следующем показе.
            image = (try? await AttachmentLoader.shared.avatar(path: avatarUrl)).flatMap(UIImage.init(data:))
        }
    }

    /// Тёплые тона фирменной палитры: гранат, золото, слива, терракота, пыльная роза, оливка.
    private static let palettes: [[Color]] = [
        [Color(rgb: 0xE2455F), Color(rgb: 0xA8213F)],
        [Color(rgb: 0xD9A45A), Color(rgb: 0x9C6A1C)],
        [Color(rgb: 0x8E4A7A), Color(rgb: 0x4E1F45)],
        [Color(rgb: 0xD4704E), Color(rgb: 0x9A3F2A)],
        [Color(rgb: 0xC98B98), Color(rgb: 0x8A4E5E)],
        [Color(rgb: 0x8C9A62), Color(rgb: 0x566236)],
    ]

    /// Цвет зависит от имени, а не от случая: у одного собеседника он одинаковый в каждой строке и после перезапуска.
    private var placeholderGradient: LinearGradient {
        let seed = name.unicodeScalars.reduce(UInt(0)) { $0 &+ UInt($1.value) }
        let colors = Self.palettes[Int(seed % UInt(Self.palettes.count))]
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}
