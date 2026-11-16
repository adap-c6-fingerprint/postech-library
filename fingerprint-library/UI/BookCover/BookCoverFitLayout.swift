import SwiftUI

nonisolated enum BookCoverFit {
    static func aspectRatio(of size: CGSize) -> CGFloat? {
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else { return nil }
        return size.width / size.height
    }

    static func fittedSize(aspectRatio: CGFloat?, in container: CGSize) -> CGSize {
        guard let aspectRatio, aspectRatio > 0, container.width > 0, container.height > 0 else { return container }
        if container.width / container.height > aspectRatio {
            return CGSize(width: container.height * aspectRatio, height: container.height)
        }
        return CGSize(width: container.width, height: container.width / aspectRatio)
    }
    // 표지 비율대로 칸 안에 들어가는 가장 큰 크기. 비율을 모르면 칸 전체를 쓴다.

    static func containerSize(width: CGFloat?, height: CGFloat?, aspectRatio: CGFloat?) -> CGSize? {
        let width = width.flatMap { $0.isFinite ? $0 : nil }
        let height = height.flatMap { $0.isFinite ? $0 : nil }
        switch (width, height, aspectRatio) {
        case let (width?, height?, _):
            return CGSize(width: width, height: height)
        case let (width?, nil, ratio?) where ratio > 0:
            return CGSize(width: width, height: width / ratio)
        case let (nil, height?, ratio?) where ratio > 0:
            return CGSize(width: height * ratio, height: height)
        default:
            return nil
        }
    }
    // 한 방향만 정해지면 나머지 방향은 표지 비율로 정한다.
}

struct BookCoverFitLayout: Layout {
    var aspectRatio: CGFloat?
    var alignment: Alignment

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        if let size = BookCoverFit.containerSize(width: proposal.width, height: proposal.height, aspectRatio: aspectRatio) {
            return size
        }
        return subviews.first?.sizeThatFits(proposal) ?? .zero
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let subview = subviews.first else { return }
        let size = BookCoverFit.fittedSize(aspectRatio: aspectRatio, in: bounds.size)
        let origin = CGPoint(
            x: bounds.minX + (bounds.width - size.width) * alignment.horizontal.fraction,
            y: bounds.minY + (bounds.height - size.height) * alignment.vertical.fraction)
        subview.place(at: origin, proposal: ProposedViewSize(size))
    }
}

struct BookCoverClipStyle<Fill: ShapeStyle>: ViewModifier {
    let cornerRadius: CGFloat
    let fill: Fill

    func body(content: Content) -> some View {
        content
            .background(fill)
            .clipShape(.rect(cornerRadius: cornerRadius))
    }
}

private extension HorizontalAlignment {
    var fraction: CGFloat {
        switch self {
        case .leading: 0
        case .trailing: 1
        default: 0.5
        }
    }
}

private extension VerticalAlignment {
    var fraction: CGFloat {
        switch self {
        case .top: 0
        case .bottom: 1
        default: 0.5
        }
    }
}
