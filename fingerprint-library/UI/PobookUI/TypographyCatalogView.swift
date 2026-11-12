#if DEBUG
import SwiftUI

/// 폰트 역할과 Dynamic Type을 함께 확인하는 개발용 카탈로그.
struct TypographyCatalogView: View {
    private let samples: [(String, PobookUI.Typography)] = [
        ("largeTitle · 화면 대표 제목", .largeTitle),
        ("title1 · 화면 제목", .title1),
        ("title2 · 섹션 제목", .title2),
        ("bookTitle · 도서명", .bookTitle),
        ("body1 · 주요 안내", .body1),
        ("body2 · 일반 본문", .body2),
        ("caption1 · 보조 설명", .caption1),
        ("caption2 · 짧은 메타데이터", .caption2),
        ("shelfHeading · 서가 안내", .shelfHeading)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ForEach(samples.indices, id: \.self) { index in
                    let (name, style) = samples[index]
                    VStack(alignment: .leading, spacing: 6) {
                        Text(name).font(.caption.monospaced()).foregroundStyle(.secondary)
                        Text("도서관에서 만나는 새로운 이야기\nPo:Book 0123456789")
                            .typography(style)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Text("강조한 청구기호 PR2993")
                    .typography(.body1.weight(.bold))
                Text("바로 안내 시작")
                    .typography(.button)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(.quaternary, in: .capsule)
                Text("다음에 찾기")
                    .typography(.buttonSmall)
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    Text("3F")
                        .typography(.caption2, scaling: .fixed)
                        .padding(12)
                        .background(.quaternary, in: .rect(cornerRadius: 12))
                    Text("그래픽에 붙는 고정 크기 예외")
                        .typography(.caption1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
        }
        .foregroundStyle(Color.textPrimary)
        .background(Color.backgroundDefault)
        .preferredColorScheme(.dark)
    }
}

#Preview("Typography · 기본") {
    TypographyCatalogView().dynamicTypeSize(.large)
}

#Preview("Typography · 접근성 큰 글자") {
    TypographyCatalogView().dynamicTypeSize(.accessibility3)
}

#Preview("Typography · 접근성 최대 글자") {
    TypographyCatalogView().dynamicTypeSize(.accessibility5)
}
#endif
