import SwiftUI

/// Круглое фото; у новых пар — фирменное кольцо, как у непросмотренных историй.
struct RingedAvatar: View {
    let photoId: String?
    let size: CGFloat
    let highlighted: Bool

    var body: some View {
        DatingPhotoView(attachmentId: photoId, cornerRadius: size / 2)
            .frame(width: size, height: size)
            .padding(highlighted ? 3 : 0)
            .background {
                if highlighted {
                    Circle().fill(Color.appBackground)
                }
            }
            .padding(highlighted ? 2.5 : 0)
            .background {
                if highlighted {
                    Circle().fill(DatingStyle.brandGradient)
                }
            }
    }
}
