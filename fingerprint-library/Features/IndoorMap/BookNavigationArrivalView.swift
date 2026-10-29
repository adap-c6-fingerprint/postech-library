import SwiftUI

/// 현재 서가의 도서 정보를 확인한 뒤 다음 목적지 또는 안내 완료를 상위 진행 상태에 전달한다.
struct BookNavigationArrivalView: View {
    let session: BookNavigationSession
    let currentStopIndex: Int
    private let bookInformation: BookNavigationBookInfo?
    private let onContinue: () -> Void
    private let onFinish: () -> Void
    private let onCancel: () -> Void

    init(session: BookNavigationSession, currentStopIndex: Int,
         bookInformation: BookNavigationBookInfo? = nil,
         onContinue: @escaping () -> Void = {}, onFinish: @escaping () -> Void = {},
         onCancel: @escaping () -> Void = {}) {
        self.session = session
        self.currentStopIndex = currentStopIndex
        self.bookInformation = bookInformation ?? BookNavigationBookInfo(session: session, stopIndex: currentStopIndex)
        self.onContinue = onContinue
        self.onFinish = onFinish
        self.onCancel = onCancel
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let bookInformation {
                    Label("서가 도착을 확인했어요", systemImage: "books.vertical")
                        .font(.title2.bold())
                    BookNavigationBookInformationView(info: bookInformation)
                    if currentStopIndex < session.stops.count - 1 {
                        Button("다음 책 안내", action: onContinue)
                            .buttonStyle(.borderedProminent)
                            .accessibilityIdentifier("book-navigation-next-stop")
                    } else {
                        Button("안내 완료", action: onFinish)
                            .buttonStyle(.borderedProminent)
                            .accessibilityIdentifier("book-navigation-finish")
                    }
                } else {
                    ContentUnavailableView("도착 정보를 확인해 주세요", systemImage: "books.vertical")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .navigationTitle("도착")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("안내 취소", action: onCancel)
                    .accessibilityIdentifier("book-navigation-arrival-cancel")
            }
        }
        .accessibilityIdentifier("book-navigation-arrival")
    }
}
