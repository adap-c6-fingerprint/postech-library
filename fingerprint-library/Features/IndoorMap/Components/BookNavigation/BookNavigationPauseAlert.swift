import SwiftUI

/// 길안내를 멈췄을 때 화면 중앙에 띄우는 확인 창.
///
/// 시스템 알림은 위치를 지정할 수 없어 ``LibraryPermissionAlert``와 같은 카드 형태로 직접 그린다.
/// 다음 책이 있으면 버튼이 세 개가 되므로 버튼을 세로로 쌓는다.
struct BookNavigationPauseAlert: View {
    let hasNextStop: Bool
    let isReroutingToNextBook: Bool
    let onResume: () -> Void
    let onNextBook: () -> Void
    let onEnd: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture(perform: onResume)
                .accessibilityHidden(true)
            card
        }
        .accessibilityAddTraits(.isModal)
        .accessibilityIdentifier("book-navigation-pause-alert")
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("안내를 잠시 멈췄어요.")
                .typography(.body1)
                .foregroundStyle(DS.ColorToken.neutralDark)
                .accessibilityAddTraits(.isHeader)
            Text("안내로 돌아가서 책을 다시 찾거나 안내를 종료할 수 있어요.")
                .typography(.caption1)
                .foregroundStyle(DS.ColorToken.neutralDark)
                .fixedSize(horizontal: false, vertical: true)
            buttons
                .padding(.top, 8)
        }
        .padding(20)
        .frame(width: 274)
        .background(Color(white: 0.87), in: RoundedRectangle(cornerRadius: 28))
        .shadow(color: .black.opacity(0.25), radius: 20, y: 8)
    }

    @ViewBuilder private var buttons: some View {
        if hasNextStop {
            VStack(spacing: 10) {
                button("다음 책 찾기", background: DS.ColorToken.primaryLight, action: onNextBook)
                    .disabled(isReroutingToNextBook)
                    .accessibilityIdentifier("book-navigation-pause-next")
                button("안내 종료하기", background: Color(white: 0.76), action: onEnd)
                    .accessibilityIdentifier("book-navigation-pause-end")
                button("돌아가기", background: Color(white: 0.76), action: onResume)
                    .accessibilityIdentifier("book-navigation-pause-resume")
            }
        } else {
            HStack(spacing: 10) {
                button("돌아가기", background: Color(white: 0.76), action: onResume)
                    .accessibilityIdentifier("book-navigation-pause-resume")
                button("안내 종료하기", background: DS.ColorToken.primaryLight, action: onEnd)
                    .accessibilityIdentifier("book-navigation-pause-end")
            }
        }
    }

    private func button(_ title: String, background: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .typography(.caption1.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(DS.ColorToken.neutralDark)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(background, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
