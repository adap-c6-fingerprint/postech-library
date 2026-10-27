import Foundation

nonisolated enum IndoorNavigationLoadError: Equatable, Sendable, LocalizedError {
    case notPrepared

    var errorDescription: String? {
        "도서관 길찾기 자료를 준비하고 있어요. 지도와 층 선택은 사용할 수 있어요."
    }
}
