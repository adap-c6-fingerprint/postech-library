import SwiftUI

/// 길안내를 멈췄을 때 화면 중앙에 띄우는 확인 창.
///
/// 시스템 알림은 위치를 지정할 수 없어 카드 형태로 직접 그린다.
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

    /// 시안 색. 버튼은 Figma "Fills/Secondary"(``Constants/FillsSecondary``)를 쓰고, 종료 동작만 빨간 글씨로 구분한다.
    private static let cardColor = Color(white: 0.77)
    private static let destructiveColor = Color(hex: 0xE5534B)

    private var message: String {
        hasNextStop
            ? "안내로 돌아가서 책을 다시 찾거나 다음 책을 찾거나, 안내를 종료할 수 있어요."
            : "안내로 돌아가서 책을 다시 찾거나 안내를 종료할 수 있어요."
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("안내를 종료할까요?")
                .typography(.body1.weight(.semibold))
                .foregroundStyle(DS.ColorToken.neutralDark)
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal, 12)
            Text(message)
                .typography(.body2)
                .foregroundStyle(DS.ColorToken.neutralDark)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            // 높이를 고정한 창에서 남는 공간은 본문과 버튼 사이에 두고, 버튼은 카드 아래에 붙인다.
            Spacer(minLength: 0)
            buttons
        }
        .padding(.horizontal, 12)
        .padding(.top, 20)
        .padding(.bottom, 14)
        // 시안 크기. 버튼이 한 줄인 한 권짜리 창은 높이를 고정하지 않아 아래에 빈 공간이 생기지 않게 한다.
        .frame(width: 300, height: hasNextStop ? 318 : nil, alignment: .top)
        // 그림자를 카드 도형에만 걸어 안쪽 버튼·글자에는 그림자가 생기지 않게 한다.
        .background {
            RoundedRectangle(cornerRadius: 28)
                .fill(Self.cardColor)
                .shadow(color: .black.opacity(0.25), radius: 20, y: 8)
        }
    }

    /// 책이 두 권 이상이면 돌아가기·다음 책 찾기·안내 종료하기를 세로로, 한 권이면 돌아가기·안내 종료하기를 가로로 둔다.
    @ViewBuilder private var buttons: some View {
        if hasNextStop {
            VStack(spacing: 8) {
                button("돌아가기", action: onResume)
                    .accessibilityIdentifier("book-navigation-pause-resume")
                button("다음 책 찾기", action: onNextBook)
                    .disabled(isReroutingToNextBook)
                    .accessibilityIdentifier("book-navigation-pause-next")
                button("안내 종료하기", isDestructive: true, action: onEnd)
                    .accessibilityIdentifier("book-navigation-pause-end")
            }
        } else {
            HStack(spacing: 8) {
                button("돌아가기", action: onResume)
                    .accessibilityIdentifier("book-navigation-pause-resume")
                button("안내 종료하기", isDestructive: true, action: onEnd)
                    .accessibilityIdentifier("book-navigation-pause-end")
            }
        }
    }

    private func button(_ title: String, isDestructive: Bool = false,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .typography(.body1.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(isDestructive ? Self.destructiveColor : DS.ColorToken.neutralDark)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(Constants.FillsSecondary, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
