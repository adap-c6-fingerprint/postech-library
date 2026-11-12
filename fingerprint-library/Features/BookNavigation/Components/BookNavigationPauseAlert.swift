import SwiftUI

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
                .foregroundStyle(PobookUI.ColorToken.neutralDark)
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal, 12)
            Text(message)
                .typography(.body2)
                .foregroundStyle(PobookUI.ColorToken.neutralDark)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            if hasNextStop { Spacer(minLength: 0) }
            buttons
        }
        .padding(.horizontal, 12)
        .padding(.top, 20)
        .padding(.bottom, 14)
        .frame(width: 300, height: hasNextStop ? 318 : nil, alignment: .top)
        .background {
            RoundedRectangle(cornerRadius: 28)
                .fill(Self.cardColor)
                .shadow(color: .black.opacity(0.25), radius: 20, y: 8)
        }
    }

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
                .foregroundStyle(isDestructive ? Self.destructiveColor : PobookUI.ColorToken.neutralDark)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(PobookUI.ColorToken.fillsSecondary, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
