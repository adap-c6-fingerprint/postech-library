import SwiftUI

/// 책 찾기와 직원 도움 안내 화면의 공통 상단바. 화면별 여백은 호출부에서 지정한다.
struct BookNavigationTopBar: View {
    let backLabel: String
    let backIdentifier: String
    let onBack: () -> Void

    var body: some View {
        HStack {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(Color.textPrimary)
                    .frame(width: 44, height: 44)
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(backLabel)
            .accessibilityIdentifier(backIdentifier)
            Spacer()
        }
        .frame(height: 48)
    }
}
