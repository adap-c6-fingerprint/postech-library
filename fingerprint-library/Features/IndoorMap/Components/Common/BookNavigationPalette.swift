import SwiftUI

enum BookNavigationPalette {
    static let accent = Color(red: 0.88, green: 1, blue: 0.18)
    static let uiAccent = UIColor(red: 0.88, green: 1, blue: 0.18, alpha: 1)
    /// 계단·엘리베이터 아이콘과 이어지는 층 이동 캡슐.
    static let floorTransition = LinearGradient(
        colors: [Color(red: 0.354, green: 0.945, blue: 0.198), Color(red: 0, green: 0.743, blue: 0.084)],
        startPoint: .top, endPoint: .bottom
    )
}
