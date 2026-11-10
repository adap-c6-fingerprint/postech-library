import SwiftUI

/// 홈·추천 탭에서 상단바 아래에 표시하는 안내 문구.
struct LibraryTabIntroText: View {
    static let topBarSpacing: CGFloat = 13.59
    let title: String
    let subtitle: String?

    init(title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing._12) {
            Text(title)
                .typography(.title1)
            if let subtitle {
                Text(subtitle)
                    .typography(.title1)
            }
        }
        .foregroundStyle(DS.ColorToken.neutralPrimary)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DS.Spacing._16)
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview("홈·추천 안내 문구") {
    VStack(alignment: .leading, spacing: 24) {
        LibraryTabIntroText(title: "오늘은 어떤 책을\n읽어볼까요?")
        LibraryTabIntroText(title: "당신에게", subtitle: "추천하는 책 6선.")
    }
    .padding(.vertical, 24)
    .background(DS.ColorToken.neutralDark)
    .preferredColorScheme(.dark)
}
#endif
