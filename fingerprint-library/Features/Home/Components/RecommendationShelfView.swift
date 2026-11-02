import SwiftUI

/// 나사와 아크릴판을 함께 배치하는 추천 캐러셀의 고정 선반.
struct RecommendationShelfView: View {
    var height: CGFloat = 106

    // Figma 2963:9772. 화면에 배치한 높이를 기준으로 장식의 비율을 유지한다.
    private enum Design {
        static let width: CGFloat = 707.25
        static let height: CGFloat = 155.458
        static let cornerRadius: CGFloat = 31.962
        static let assetSize = CGSize(width: 721, height: 170)
        static let assetTopInset: CGFloat = 3.417
        static let fillOpacity: Double = 0.2
        static let edgeInset: CGFloat = 1.5
        static let boltSize: CGFloat = 17.083
        static let boltX: CGFloat = 17.083
        static let boltY: CGFloat = 70.041
    }

    var body: some View {
        GeometryReader { geometry in
            let scale = height / Design.height
            let horizontalScale = max(geometry.size.width / Design.width, scale)
            let assetWidth = Design.assetSize.width * horizontalScale
            let assetHeight = Design.assetSize.height * scale
            let leadingInset = (Design.assetSize.width - Design.width) / 2 * horizontalScale
            let topInset = Design.assetTopInset * scale

            ZStack {
                // Frost의 근사치. Liquid Glass의 가장자리 굴절은 적용하지 않는다.
                PlateOutline()
                    .fill(.ultraThinMaterial)
                    .opacity(0.4)

                PlateOutline()
                    .fill(DS.lime.C5E300.opacity(Design.fillOpacity))

                // 원본 PNG의 채움만 가리고 테두리·반사광·그림자를 보존한다.
                Image("RecommendationGlass")
                    .resizable()
                    .mask {
                        Rectangle()
                            .fill(.white)
                            .overlay {
                                PlateOutline(inset: Design.edgeInset)
                                    .fill(.black)
                            }
                            .compositingGroup()
                            .luminanceToAlpha()
                    }
            }
                .frame(width: assetWidth, height: assetHeight)
                // PNG 여백이 아니라 판 본체를 기준으로 높이와 나사 위치를 맞춘다.
                .offset(x: -leadingInset, y: -topInset)
                .frame(
                    width: geometry.size.width,
                    height: height,
                    alignment: .topLeading
                )
                .mask {
                    // 오른쪽 화면 경계에서만 자르고 바깥 그림자는 남긴다.
                    Rectangle()
                        .padding(.leading, -leadingInset)
                        .padding(.vertical, -(assetHeight - height))
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
