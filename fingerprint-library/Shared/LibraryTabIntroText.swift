import SwiftUI

/// 홈·추천 탭에서 상단바 아래에 표시하는 안내 문구.
struct LibraryTabIntroText: View {
    static let topBarSpacing: CGFloat = 13.59
    let title: String

    var body: some View {
        Text(title)
            .typography(.title1)
            .foregroundStyle(PobookUI.ColorToken.neutralPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, PobookUI.Spacing._16)
    }
}

#if DEBUG
#Preview("홈·추천 안내 문구") {
    VStack(alignment: .leading, spacing: 24) {
        LibraryTabIntroText(title: "오늘은 어떤 책을\n읽어볼까요?")
        LibraryTabIntroText(title: "당신에게\n추천하는 책 6선.")
    }
    .padding(.vertical, 24)
    .background(PobookUI.ColorToken.neutralDark)
    .preferredColorScheme(.dark)
}
#endif
