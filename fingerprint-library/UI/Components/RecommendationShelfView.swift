import SwiftUI

struct RecommendationShelfView: View {
    static let leadingInset: CGFloat = 16
    static let recommendationCornerRadius: CGFloat = 10
    static let carouselSpace = "recommendationCarousel"
    static let thinHeight: CGFloat = 54

    static func thin(width: CGFloat? = nil) -> RecommendationShelfView {
        RecommendationShelfView(
            height: thinHeight,
            width: width,
            fillOpacity: 0.5,
            fixedBoltSize: 17.08,
            fixedBoltLeadingInset: 15,
            cornerRadius: recommendationCornerRadius
        )
    }

    var height: CGFloat = 106
    var width: CGFloat? = nil
    var fillOpacity: Double = 0.5
    var fixedBoltSize: CGFloat? = nil
    var fixedBoltLeadingInset: CGFloat? = nil
    var cornerRadius: CGFloat? = nil

    private nonisolated enum Design {
        static let width: CGFloat = 707.25
        static let height: CGFloat = 155.458
        static let cornerRadius: CGFloat = 31.962
        static let assetSize = CGSize(width: 721, height: 170)
        static let assetTopInset: CGFloat = 3.417
        static let edgeMaskOutset: CGFloat = 2
        static let boltSize: CGFloat = 17.083
        static let boltX: CGFloat = 17.083
        static let boltY: CGFloat = 70.041
    }

    var body: some View {
        GeometryReader { geometry in
            let scale = height / Design.height
            let plate = CGRect(x: 0, y: 0, width: width ?? geometry.size.width, height: height)
            let asset = Self.assetFrame(for: plate)

            ZStack {
                PlateOutline(cornerRadius: cornerRadius)
                    .fill(Color.limeDark.opacity(fillOpacity))

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
                .offset(x: asset.minX, y: asset.minY)
                .frame(
                    width: geometry.size.width,
                    height: height,
                    alignment: .topLeading
                )
                .mask {
                    Rectangle()
                        .padding(.leading, asset.minX)
                        .padding(.vertical, -(asset.height - height))
                }
                .overlay(alignment: .topLeading) {
                    let boltSize = fixedBoltSize ?? Design.boltSize * scale
                    let boltTopInset = fixedBoltSize == nil ? Design.boltY * scale : (height - boltSize) / 2
                    let boltLeadingInset = fixedBoltLeadingInset ?? Design.boltX * scale

                    Image("Bolt")
                        .resizable()
                        .scaledToFit()
                        .frame(width: boltSize, height: boltSize)
                        .padding(.leading, boltLeadingInset)
                        .padding(.top, boltTopInset)
                }
        }
        .frame(height: height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

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
        var width: CGFloat? = nil
        var cornerRadius: CGFloat? = nil
        @Environment(\.layoutDirection) private var layoutDirection
        private let blurRadius: CGFloat = 8

        func body(content: Content) -> some View {
            GeometryReader { geometry in
                let cover = content.frame(width: geometry.size.width, height: geometry.size.height)
                if let carousel = geometry.bounds(of: .named(RecommendationShelfView.carouselSpace)) {
                    let leadingInset = RecommendationShelfView.leadingInset
                    let availableWidth = max(0, carousel.width - leadingInset)
                    let carouselLeading = layoutDirection == .leftToRight
                        ? carousel.minX
                        : geometry.size.width - carousel.maxX
                    let plate = CGRect(
                        x: carouselLeading + leadingInset,
                        y: carousel.maxY - height,
                        width: width ?? availableWidth,
                        height: height
                    )
                    let outline = PlateOutline(cornerRadius: cornerRadius)
                        .path(in: RecommendationShelfView.assetFrame(for: plate))
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

    private nonisolated struct PlateOutline: Shape {
        var inset: CGFloat = 0
        var cornerRadius: CGFloat? = nil

        func path(in rect: CGRect) -> Path {
            let plateBounds = CGRect(
                x: (Design.assetSize.width - Design.width) / 2,
                y: Design.assetTopInset,
                width: Design.width,
                height: Design.height
            ).insetBy(dx: inset, dy: inset)
            let transform = CGAffineTransform(
                a: rect.width / Design.assetSize.width, b: 0,
                c: 0, d: rect.height / Design.assetSize.height,
                tx: rect.minX, ty: rect.minY
            )
            if let cornerRadius {
                return UnevenRoundedRectangle(
                    topLeadingRadius: cornerRadius,
                    bottomLeadingRadius: cornerRadius,
                    style: .circular
                ).path(in: plateBounds.applying(transform))
            }

            let shape = UnevenRoundedRectangle(
                topLeadingRadius: max(0, Design.cornerRadius - inset),
                topTrailingRadius: max(0, Design.cornerRadius - inset),
                style: .circular
            )
            return shape.path(in: plateBounds).applying(transform)
        }
    }
}
