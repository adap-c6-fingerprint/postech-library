import Foundation

nonisolated enum BookDetailSheetDetent: CaseIterable {
    case compact, medium, large
}

nonisolated enum BookDetailCompactLayout {
    static let coverSize = CGSize(width: 140, height: 186)
    static let topPadding: CGFloat = 8
    static let horizontalPadding: CGFloat = 16
    static let actionsHeight: CGFloat = 66
    static let coverAspectRatio = coverSize.width / coverSize.height

    static func height(coverHeight: CGFloat) -> CGFloat {
        let coverHeight = coverHeight.isFinite && coverHeight > 0 ? coverHeight : coverSize.height
        return topPadding + coverHeight + actionsHeight
    }
}
