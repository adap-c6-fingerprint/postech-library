import SwiftUI

/// 나사와 아크릴판을 함께 배치하는 추천 캐러셀의 고정 선반.
struct RecommendationShelfView: View {
    static let leadingInset: CGFloat = 16
    static let carouselSpace = "recommendationCarousel"

    var height: CGFloat = 106

    // Figma 2963:9772. 화면에 배치한 높이를 기준으로 장식의 비율을 유지한다.
    private enum Design {
        static let width: CGFloat = 707.25
        static let height: CGFloat = 155.458
        static let cornerRadius: CGFloat = 31.962
        static let assetSize = CGSize(width: 721, height: 170)
        static let assetTopInset: CGFloat = 3.417
        static let fillOpacity: Double = 0.5
        static let edgeMaskOutset: CGFloat = 2
        static let boltSize: CGFloat = 17.083
        static let boltX: CGFloat = 17.083
        static let boltY: CGFloat = 70.041
    }

    var body: some View {
        GeometryReader { geometry in
            let scale = height / Design.height
            let plate = CGRect(x: 0, y: 0, width: geometry.size.width, height: height)
            let asset = Self.assetFrame(for: plate)

            ZStack {
                PlateOutline()
                    .fill(Color.limeDark.opacity(Design.fillOpacity))

                // PNG의 채움과 라임색 가장자리를 가리고 바깥 그림자를 남긴다.
                Image("RecommendationGlass")
                    .resizable()
                    .mask {
                        Rectangle()
                            .fill(.white)
                            .overlay {
                                PlateOutline(inset: -Design.edgeMaskOutset)
                                    .fill(.black)
                            }
                            .compositingGroup()
                            .luminanceToAlpha()
                    }
            }
                .frame(width: asset.width, height: asset.height)
                // PNG 여백이 아니라 판 본체를 기준으로 높이와 나사 위치를 맞춘다.
                .offset(x: asset.minX, y: asset.minY)
                .frame(
                    width: geometry.size.width,
                    height: height,
                    alignment: .topLeading
                )
                .mask {
                    // 오른쪽 화면 경계에서만 자르고 바깥 그림자는 남긴다.
                    Rectangle()
                        .padding(.leading, asset.minX)
                        .padding(.vertical, -(asset.height - height))
                }
                .overlay(alignment: .topLeading) {
                    Image("Bolt")
                        .resizable()
                        .scaledToFit()
                        .frame(width: Design.boltSize * scale, height: Design.boltSize * scale)
                        .padding(.leading, Design.boltX * scale)
                        .padding(.top, Design.boltY * scale)
                }
        }
        .frame(height: height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// 판을 그릴 때와 표지를 가릴 때 같은 PNG 좌표를 사용한다.
    private static func assetFrame(for plate: CGRect) -> CGRect {
        let scale = plate.height / Design.height
        let horizontalScale = max(plate.width / Design.width, scale)
        let horizontalInset = (Design.assetSize.width - Design.width) / 2 * horizontalScale
        return CGRect(
            x: plate.minX - horizontalInset,
            y: plate.minY - Design.assetTopInset * scale,
            width: Design.assetSize.width * horizontalScale,
            height: Design.assetSize.height * scale
        )
    }

    struct CoverBlur: ViewModifier {
        let height: CGFloat
        @Environment(\.layoutDirection) private var layoutDirection
        private let blurRadius: CGFloat = 2

        func body(content: Content) -> some View {
            GeometryReader { geometry in
                let cover = content.frame(width: geometry.size.width, height: geometry.size.height)
                if let carousel = geometry.bounds(of: .named(RecommendationShelfView.carouselSpace)) {
                    let plate = CGRect(
                        x: carousel.minX + (layoutDirection == .leftToRight ? RecommendationShelfView.leadingInset : 0),
                        y: carousel.maxY - height,
                        width: max(0, carousel.width - RecommendationShelfView.leadingInset),
                        height: height
                    )
                    let outline = PlateOutline().path(in: RecommendationShelfView.assetFrame(for: plate))
                    let coverBounds = Path(CGRect(origin: .zero, size: geometry.size))
                    let blurPadding = blurRadius * 3

                    cover
                        .mask { coverBounds.subtracting(outline).fill(.white) }
                        .overlay {
                            cover
                                .padding(blurPadding)
                                .blur(radius: blurRadius)
                                .mask { outline.offsetBy(dx: blurPadding, dy: blurPadding).fill(.white) }
                                .padding(-blurPadding)
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                        }
                        .contentShape(Rectangle())
                } else {
                    cover
                }
            }
        }
    }

    /// PNG의 바깥 여백과 그림자를 제외한 판 본체의 외곽.
    private struct PlateOutline: Shape {
        var inset: CGFloat = 0

        func path(in rect: CGRect) -> Path {
            let plateBounds = CGRect(
                x: (Design.assetSize.width - Design.width) / 2,
                y: Design.assetTopInset,
                width: Design.width,
                height: Design.height
            ).insetBy(dx: inset, dy: inset)
            let shape = UnevenRoundedRectangle(
                topLeadingRadius: max(0, Design.cornerRadius - inset),
                topTrailingRadius: max(0, Design.cornerRadius - inset),
                style: .circular
            )
            let transform = CGAffineTransform(
                a: rect.width / Design.assetSize.width, b: 0,
                c: 0, d: rect.height / Design.assetSize.height,
                tx: rect.minX, ty: rect.minY
            )
            return shape.path(in: plateBounds).applying(transform)
        }
    }
}
