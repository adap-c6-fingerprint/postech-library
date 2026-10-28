import SwiftUI

/// 도착 화면 후속 개발 진입점. 안내 원본과 현재 목적지 인덱스를 그대로 전달받는다.
struct BookNavigationArrivalView: View {
    let session: BookNavigationSession
    let currentStopIndex: Int

    var body: some View {
        ContentUnavailableView(
            "실시간 길안내 - 도착",
            systemImage: "books.vertical",
            description: Text("도착 화면은 개발 예정이에요.")
        )
        .navigationTitle("도착")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("book-navigation-arrival")
    }
}
