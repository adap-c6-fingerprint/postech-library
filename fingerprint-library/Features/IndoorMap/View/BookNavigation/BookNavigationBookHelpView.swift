import SwiftUI

/// 서가에서 찾지 못한 책의 제목·청구기호를 직원에게 보여 줄 수 있는 안내 화면.
struct BookNavigationBookHelpView: View {
    let info: BookNavigationBookInfo
    let hasNextStop: Bool
    let onContinue: () -> Void
    let onDefer: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var holding: BookHolding? { BookHoldingPresentation.preferred(in: info.holdings) }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 0) {
                        message
                            .padding(.top, max(24, min(80, geometry.size.height * 0.15)))
                        bookCard
                            .padding(.top, 48)
                            .padding(.bottom, 24)
                    }
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { actions }
        .background { Color.backgroundDefault.ignoresSafeArea() }
        .foregroundStyle(Color.textPrimary)
        .toolbar(.hidden, for: .navigationBar, .tabBar)
        .preferredColorScheme(.dark)
        .accessibilityIdentifier("book-navigation-book-help")
    }

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 22))
                    .frame(width: 44, height: 44)
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("책 찾기 화면으로 돌아가기")
            .accessibilityIdentifier("book-navigation-book-help-back")
            Spacer()
        }
        .frame(height: 48)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var message: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle().fill(Color.limeBase)
                Image(systemName: "info")
                    .font(.system(size: 35, weight: .bold))
                    .foregroundStyle(Color.backgroundDefault)
            }
            .frame(width: 69, height: 69)
            .accessibilityHidden(true)
            Text("도서관 직원에게\n도움을 청해보세요")
                .typography(.title1)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 28)
                .accessibilityAddTraits(.isHeader)
            Text("도서 이름과 청구 기호를 함께\n직원에게 보여주세요")
                .typography(.body2)
                .foregroundStyle(Color.textTertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
        }
    }

    private var bookCard: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16)) // 이거 사실상 HStackLayout만 보여줌
            : AnyLayout(HStackLayout(alignment: .top, spacing: 20))
        return layout {
            BookCoverView(url: info.book.imageURL, isbn: info.book.isbn)
                .frame(width: 78, height: 112)
                .background(.quaternary, in: .rect(cornerRadius: 8))
                .clipShape(.rect(cornerRadius: 8))
                .accessibilityIdentifier("book-navigation-book-help-cover")
            VStack(alignment: .leading, spacing: 3) {
                Text(BookText.plainText(info.book.title))
                    .typography(.bookTitle)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("book-navigation-book-help-title")
                Text([info.floorName, info.callNumbers.isEmpty ? "청구기호 확인 필요" : info.callNumbers.joined(separator: " · ")]
                    .compactMap { $0 }.joined(separator: " "))
                    .typography(.body2)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("book-navigation-book-help-call-number")
                Text(BookText.plainText(info.book.author))
                    .typography(.caption2)
                    .foregroundStyle(Color.textTertiary)
                Text(holding?.availabilityText ?? "대출 상태 확인 필요")
                    .typography(.caption1)
                    .foregroundStyle(holding?.availability == "available" ? Color.green : Color.textTertiary)
                    .padding(.top, 17)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(white: 0.16), in: .rect(cornerRadius: 20))
        .accessibilityIdentifier("book-navigation-book-help-card")
    }

    private var actions: some View {
        VStack(spacing: 12) {
            Button {
                if hasNextStop {
                    onContinue()
                } else {
                    // 데스크 위치와 경로 연결 전에는 목적지나 경유지를 추가하지 않는다.
                    onDefer()
                }
            } label: {
                Text("다음 책 찾고 대출 데스크로 안내 받기")
                    .typography(.body2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(Color.backgroundDefault)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .contentShape(.capsule)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.tint(Color.limeBase).interactive(), in: .capsule)
            .accessibilityHint(hasNextStop ? "다음 책의 경로로 안내해요" : "전체 경로 안내를 종료해요")
            .accessibilityIdentifier("book-navigation-book-help-continue")
            Button(action: onDefer) {
                Text(hasNextStop ? "안내 종료하기" : "다음에 찾기.")
                    .typography(.body2)
                    .underline()
                    .foregroundStyle(Color.textTertiary)
                    .frame(minHeight: 28)
            }
            .buttonStyle(.plain)
            .accessibilityHint("전체 경로 안내를 종료해요")
            .accessibilityIdentifier("book-navigation-book-help-defer")
        }
        .padding(.horizontal, 36)
        .padding(.top, 16)
        .padding(.bottom, 18)
    }
}

#if DEBUG
#Preview("직원 도움 안내 · 마지막 책") {
    NavigationStack {
        BookNavigationBookHelpView(
            info: .init(previewTitle: "푸울에 풍덩", callNumber: "PR2993 .F2 .P45"),
            hasNextStop: false, onContinue: {}, onDefer: {}
        )
    }
}

#Preview("직원 도움 안내 · 다음 책 있음") {
    NavigationStack {
        BookNavigationBookHelpView(
            info: .init(previewTitle: "블렌더 3D 모델링 & 렌더링", callNumber: "TR897.7 .쓰298 2023"),
            hasNextStop: true, onContinue: {}, onDefer: {}
        )
    }
}
#endif
