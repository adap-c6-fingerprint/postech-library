import Foundation

nonisolated enum BookDetailSheetDetent: CaseIterable {
    case compact, medium, large
}

/// 표지와 하단 버튼을 시트 내부에 배치하기 위한 최소 높이.
nonisolated enum BookDetailCompactLayout {
    static let coverSize = CGSize(width: 140, height: 186)
    static let topPadding: CGFloat = 8
    static let horizontalPadding: CGFloat = 16
    static let actionsHeight: CGFloat = 66
    // UIKit이 하단 safe area를 더하므로 여기에는 콘텐츠 높이만 포함한다.
    static let height = topPadding + coverSize.height + actionsHeight
}
