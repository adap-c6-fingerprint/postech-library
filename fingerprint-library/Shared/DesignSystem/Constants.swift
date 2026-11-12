import SwiftUI

/// Figma Dev Mode가 내보내는 변수 이름 그대로 쓰는 색.
///
/// 시안 코드를 그대로 옮겨 쓸 수 있게 이름을 맞춘다. 값은 Apple 시스템 색을 따라 라이트·다크에서 바뀐다.
enum Constants {
    /// Figma "Fills/Secondary". 라이트 rgba(120,120,128,0.16), 다크 rgba(120,120,128,0.32).
    static let FillsSecondary = Color(uiColor: .secondarySystemFill)
}
