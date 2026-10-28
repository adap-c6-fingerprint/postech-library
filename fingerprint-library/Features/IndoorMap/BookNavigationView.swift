import SwiftUI

/// 후속 개발 진입점. 확정된 입력만 받고 위치 추적·재탐색·도착 판정은 아직 시작하지 않는다.
struct BookNavigationView: View {
    let session: BookNavigationSession
    @State private var currentStopIndex = 0
    @State private var isArrivalPresented = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                ContentUnavailableView("실시간 길안내", systemImage: "location.north.line",
                    description: Text("도서 \(session.stops.count)권의 경로 정보를 받았어요. 실시간 안내 화면은 개발 예정이에요."))

                Button("도착 화면 열기 (테스트)") {
                    isArrivalPresented = true
                }
                .buttonStyle(.borderedProminent)
                .disabled(!session.stops.indices.contains(currentStopIndex))
                .accessibilityIdentifier("book-navigation-arrival-trigger")
            }
                .navigationDestination(isPresented: $isArrivalPresented) {
                    BookNavigationArrivalView(
                        session: session, currentStopIndex: currentStopIndex)
                }
                .navigationTitle("실시간 길안내")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar(.visible, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("뒤로가기", systemImage: "chevron.left") { dismiss() }
                            .accessibilityIdentifier("book-navigation-back")
                    }
                }
        }
        .preferredColorScheme(.dark)
        .accessibilityIdentifier("book-navigation")
    }
}
