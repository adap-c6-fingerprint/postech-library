import SwiftUI

/// 어느 깊이의 화면에서도 홈 지도 탭으로 돌아갈 수 있게 앱 루트가 넣어 주는 동작.
///
/// 띄워 둔 상세·책바구니 화면을 닫고 홈 탭을 선택한다. 주입되지 않은 미리보기에서는 nil이다.
private struct LibraryGoHomeKey: EnvironmentKey {
    static var defaultValue: (() -> Void)? { nil }
}

extension EnvironmentValues {
    var libraryGoHome: (() -> Void)? {
        get { self[LibraryGoHomeKey.self] }
        set { self[LibraryGoHomeKey.self] = newValue }
    }
}
