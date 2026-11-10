import Foundation

nonisolated struct BookRoutePreviewPanelState: Equatable {
    var isExpanded = false
    var isMoving = false
    var isContentAtTop = true
    var dragProgress: CGFloat?

    var showsFullDescription: Bool { isExpanded || isMoving }
    var expansionProgress: CGFloat { dragProgress ?? (isExpanded ? 1 : 0) }

    func canBeginDrag(translation: CGSize) -> Bool {
        guard abs(translation.height) > abs(translation.width) else { return false }
        // 펼친 카드에서는 설명 스크롤을 우선하고, 맨 위에서 아래로 당길 때만 접는다.
        return !isExpanded || (translation.height > 0 && isContentAtTop)
    }

    func targetIsExpanded(translation: CGFloat, predictedTranslation: CGFloat) -> Bool {
        if isExpanded {
            return !(translation >= 48 || predictedTranslation >= 80)
        }
        return translation <= -48 || predictedTranslation <= -80
    }
}

nonisolated enum BookPreviewSheetLayout {
    static let collapsedCardHeight: CGFloat = 376

    static func fullSize(contentSize: CGSize, top: CGFloat, bottom: CGFloat,
                         leading: CGFloat = 0, trailing: CGFloat = 0) -> CGSize {
        CGSize(width: contentSize.width + leading + trailing,
               height: contentSize.height + top + bottom)
    }

    static func progress(height: CGFloat, minimum: CGFloat, maximum: CGFloat, isExpanded: Bool) -> CGFloat {
        guard maximum > minimum else { return isExpanded ? 1 : 0 }
        return min(1, max(0, (height - minimum) / (maximum - minimum)))
    }
}
