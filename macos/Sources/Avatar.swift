import SwiftUI

// Karakter avatarı; şef (ördek) için tüy, gaga ve yıldız rozeti eklenir
struct CuteBlobAvatar: View {
    let color: Color
    let shapeType: Int
    let size: CGFloat
    var showStarBadge: Bool = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ZStack {
                Circle()
                    .fill((showStarBadge ? Color(red: 1.0, green: 0.78, blue: 0.14) : color).opacity(0.28))
                    .frame(width: size * 1.15, height: size * 1.15)
                    .blur(radius: size * 0.16)

                if showStarBadge {
                    HStack(spacing: -size * 0.03) {
                        Capsule()
                            .fill(Color(red: 1.0, green: 0.86, blue: 0.18))
                            .frame(width: size * 0.13, height: size * 0.22)
                            .rotationEffect(.degrees(-18))
                        Capsule()
                            .fill(Color(red: 0.99, green: 0.76, blue: 0.10))
                            .frame(width: size * 0.11, height: size * 0.18)
                            .rotationEffect(.degrees(16))
                    }
                    .offset(x: size * 0.01, y: -size * 0.45)
                }

                blobShape
                    .fill(
                        LinearGradient(
                            colors: showStarBadge
                                ? [Color(red: 1.0, green: 0.88, blue: 0.22), Color(red: 0.98, green: 0.64, blue: 0.06)]
                                : [color, color.opacity(0.82)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: size, height: size * 0.92)
                    .rotationEffect(.degrees(showStarBadge ? 0 : (shapeType == 1 ? -8 : (shapeType == 2 ? 6 : -4))))

                HStack(spacing: size * 0.14) {
                    eye
                    eye
                }
                .offset(x: showStarBadge ? 0 : size * 0.06, y: showStarBadge ? -size * 0.07 : -size * 0.02)

                if showStarBadge {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 1.0, green: 0.45, blue: 0.08), Color(red: 0.90, green: 0.26, blue: 0.03)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: size * 0.36, height: size * 0.17)
                        .offset(y: size * 0.14)
                }
            }

            if showStarBadge {
                ZStack {
                    Circle()
                        .fill(Color(red: 0.98, green: 0.55, blue: 0.08))
                        .frame(width: size * 0.32, height: size * 0.32)
                    Image(systemName: "star.fill")
                        .font(.system(size: size * 0.16, weight: .bold))
                        .foregroundStyle(.white)
                }
                .offset(x: 2, y: 2)
            }
        }
    }

    private var eye: some View {
        ZStack(alignment: .topLeading) {
            Capsule()
                .fill(Color.black.opacity(0.84))
                .frame(width: size * 0.095, height: size * 0.23)
            Circle()
                .fill(Color.white.opacity(0.92))
                .frame(width: size * 0.036, height: size * 0.036)
                .offset(x: size * 0.02, y: size * 0.035)
        }
        .rotationEffect(.degrees(showStarBadge ? 0 : -8))
    }

    private var blobShape: RoundedRectangle {
        switch shapeType {
        case 1: return RoundedRectangle(cornerRadius: size * 0.34, style: .continuous)
        case 2: return RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
        default: return RoundedRectangle(cornerRadius: size * 0.48, style: .continuous)
        }
    }
}
