import SwiftUI

struct LibraryUnderlinedButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .typography(.body2.weight(.medium))
                .underline()
                .foregroundStyle(Color.textTertiary)
                .frame(minHeight: 28)
        }
        .buttonStyle(.plain)
    }
}

#if DEBUG
#Preview("밑줄 텍스트 버튼") {
    VStack(spacing: 12) {
        LibraryUnderlinedButton(title: "못 찾았어요.", action: {})
        LibraryUnderlinedButton(title: "안내 종료하기", action: {})
        LibraryUnderlinedButton(title: "다음에 찾기.", action: {})
    }
    .padding(24)
    .background(Color.backgroundDefault)
    .preferredColorScheme(.dark)
}
#endif
