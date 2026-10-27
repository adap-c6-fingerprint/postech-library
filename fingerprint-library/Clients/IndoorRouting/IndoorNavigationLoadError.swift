import Foundation

/// 도면은 표시할 수 있으나 길찾기 데이터셋이 아직 없는 상태를 나타낸다.
///
/// 지도 자체의 로딩 오류와 구분해, 화면에서 지도·층 선택을 유지하면서 상태를 안내한다.
nonisolated enum IndoorNavigationLoadError: Equatable, Sendable, LocalizedError {
    /// 도서관 폴더에 길찾기 데이터셋 manifest가 아직 준비되지 않았다.
    case notPrepared

    /// 지도 표시를 계속 사용할 수 있음을 함께 알려주는 사용자 안내 문구.
    var errorDescription: String? {
        "도서관 길찾기 자료를 준비하고 있어요. 지도와 층 선택은 사용할 수 있어요."
    }
}
