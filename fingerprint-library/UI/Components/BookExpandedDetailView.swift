import SwiftUI

// ✅ 시트를 끝까지 올렸을 때 보이는 책 상세 화면의 스크롤 콘텐츠.
// ✅ 단권은 표지 한 장, 여러 권은 좌우로 넘기는 표지 캐러셀과 페이지 표시를 보여 준다.
// ✅ 스크롤 뷰·상단 버튼·하단 버튼은 각 화면이 소유하고, 표지 아래 정보는 `details`로 받는다.
struct BookExpandedDetailView<Details: View>: View {
    // ✅ 권수가 아니라 화면 종류로 분기한다. 여러 권 미리보기는 1권이어도 캐러셀 디자인을 사용한다.
    enum Style {
        case single
        case carousel
    }

    let style: Style
    let books: [Book]
    @Binding var selectedBookID: Book.ID?
    var coverTopPadding: CGFloat = BookExpandedDetailLayout.coverTopPadding
    var identifierPrefix = "bookExpandedDetail"
    /// 단권 상세가 이미 받아 둔 표지 캐시 주소. 여러 권은 각 표지를 따로 불러온다.
    var cachedCoverURL: URL?
    @ViewBuilder let details: (Book) -> Details

    @State private var containerWidth: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isMultiple: Bool { style == .carousel }

    private var selectedIndex: Int {
        books.firstIndex { $0.id == selectedBookID } ?? 0
    }

    private var selectedBook: Book? {
        books.indices.contains(selectedIndex) ? books[selectedIndex] : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isMultiple {
                coverCarousel
                pageIndicator
            } else if let book = selectedBook {
                cover(book)
                    .frame(maxWidth: .infinity)
                    .padding(.top, coverTopPadding)
                    .accessibilityIdentifier("\(identifierPrefix).expandedCover")
            }
            if let selectedBook {
                details(selectedBook)
                    .padding(.top, BookExpandedDetailLayout.detailsTopPadding)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { containerWidth = $0 }
    }

    @ViewBuilder
    private func cover(_ book: Book) -> some View {
        let cover = BookCoverView(
            url: book.imageURL, isbn: book.isbn, cachedURL: isMultiple ? nil : cachedCoverURL,
            imageCornerRadius: isMultiple ? BookExpandedDetailLayout.carouselCoverCornerRadius : 0) // ✅
            .frame(width: BookExpandedDetailLayout.coverSize.width,
                   height: BookExpandedDetailLayout.coverSize.height)
        if isMultiple {
            // ✅ 표지 비율이 칸과 달라도 남는 영역에 회색 배경이 보이지 않게 한다.
            // ✅ 배경이 없으므로 그림자도 실제 표지 이미지 모양에만 생긴다.
            cover.shadow(color: .black.opacity(0.3), radius: 18, y: 8)
        } else {
            cover
                .background(.quaternary)
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .shadow(color: .black.opacity(0.3), radius: 18, y: 8)
        }
    }

    // MARK: - 여러 권

    /// 선택한 표지를 가운데에 두고 다음 표지를 작게 보여 준다. 표지를 넘기면 아래 정보도 같은 책으로 바뀐다.
    @ViewBuilder
    private var coverCarousel: some View {
        let shadowInset = BookExpandedDetailLayout.carouselShadowInset
        let height = BookExpandedDetailLayout.coverSize.height + shadowInset * 2
        // 너비를 알기 전에 그리면 가운데 정렬 여백이 0이라 첫 위치가 어긋난다.
        if containerWidth > 0 {
            let coverWidth = BookExpandedDetailLayout.coverSize.width
            let sideMargin = max(0, (containerWidth - coverWidth) / 2)
            let viewportWidth = containerWidth
            ScrollView(.horizontal) {
                LazyHStack(spacing: BookExpandedDetailLayout.carouselSpacing) {
                    ForEach(books) { book in
                        cover(book)
                            .visualEffect { content, proxy in
                                content.scaleEffect(
                                    BookExpandedDetailLayout.carouselScale(
                                        midX: proxy.frame(in: .scrollView).midX, viewportWidth: viewportWidth),
                                    anchor: .bottom)
                            }
                            .id(book.id)
                            .accessibilityHidden(true)
                    }
                }
                .padding(.vertical, shadowInset)
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $selectedBookID, anchor: .center)
            .contentMargins(.horizontal, sideMargin, for: .scrollContent)
            .frame(height: height)
            .padding(.top, coverTopPadding - shadowInset)
            .padding(.bottom, -shadowInset)
            .accessibilityIdentifier("\(identifierPrefix).coverCarousel")
        } else {
            Color.clear
                .frame(height: height)
                .padding(.top, coverTopPadding - shadowInset)
                .padding(.bottom, -shadowInset)
        }
    }

    /// 현재 선택한 책의 순서를 숫자와 점으로 표시한다. VoiceOver에서는 위·아래 쓸기로 책을 바꾼다.
    private var pageIndicator: some View {
        let index = selectedIndex
        return HStack(spacing: 10) {
            Text("\(index + 1)/\(books.count)")
                .typography(.caption2)
                .foregroundStyle(PobookUI.ColorToken.primaryLight)
            HStack(spacing: 8) {
                ForEach(books.indices, id: \.self) { offset in
                    Capsule()
                        .fill(offset == index ? PobookUI.ColorToken.primaryLight : Color.white.opacity(0.45))
                        .frame(width: offset == index ? 20 : 8, height: 8)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.horizontal, BookExpandedDetailLayout.indicatorHorizontalPadding)
        .padding(.top, BookExpandedDetailLayout.indicatorTopPadding)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: index)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("책 선택")
        .accessibilityValue(
            "\(books.count)권 중 \(index + 1)번째, \(selectedBook.map { BookText.plainText($0.title) } ?? "")")
        .accessibilityAdjustableAction { direction in
            let next: Int
            switch direction {
            case .increment: next = min(books.count - 1, index + 1)
            case .decrement: next = max(0, index - 1)
            @unknown default: return
            }
            guard next != index else { return }
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
                selectedBookID = books[next].id
            }
        }
        .accessibilityIdentifier("\(identifierPrefix).pageIndicator")
    }
}

// ✅ 펼친 상세 화면의 도보 거리와 층 이동 횟수 표시. 아이콘 색 외에도 접근성 문구로 의미를 전달한다.
struct BookExpandedRouteSummary: View {
    let distanceText: String
    let floorChangeCount: Int

    var body: some View {
        HStack(spacing: 16) {
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                icon("figure.walk", size: 18, color: Color(white: 0.45))
                Text(distanceText)
                    .typography(.caption1)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("이동 거리 \(distanceText)")
            HStack(spacing: 6) {
                icon("arrow.up.arrow.down.square", size: 16, color: .green)
                Text("\(floorChangeCount)회")
                    .typography(.caption1)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("층 이동 \(floorChangeCount)회")
        }
        .typography(.caption1)
        .foregroundStyle(Color.textSecondary)
    }

    private func icon(_ name: String, size: CGFloat, color: Color) -> some View {
        Image(systemName: name)
            .font(.system(size: size, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: 28, height: 28)
            .background(color, in: Circle())
            .accessibilityHidden(true)
    }
}

// ✅ 펼친 상세 화면의 표지·캐러셀 치수. 시안 기준 402 × 874 화면에서 맞췄다.
nonisolated enum BookExpandedDetailLayout {
    static let coverSize = CGSize(width: 218, height: 310)
    static let coverTopPadding: CGFloat = 30
    static let detailsTopPadding: CGFloat = 24
    static let carouselSpacing: CGFloat = 8
    /// 표지 그림자가 가로 스크롤 영역에서 잘리지 않도록 위아래에 둔 여백.
    static let carouselShadowInset: CGFloat = 28
    /// 옆 표지는 바닥을 맞춘 채 이 비율만큼 줄어든다.
    static let sideCoverScale: CGFloat = 0.82
    static let indicatorTopPadding: CGFloat = 16
    static let indicatorHorizontalPadding: CGFloat = 16 // ✅ 시안: 마지막 점이 화면 오른쪽에서 16pt
    /// ✅ 시안: 여러 권 표지 윗변이 화면 위에서 127pt. 스크롤 상단 바(안전 영역 62 + 버튼 44) 아래로 21pt를 둔다.
    static let carouselCoverTopPadding: CGFloat = 21
    /// ✅ 여러 권 화면의 표지 이미지 모서리.
    static let carouselCoverCornerRadius: CGFloat = 8
    /// ✅ 시안: 여러 권 펼친 화면의 하단 버튼은 홈 인디케이터 안전 영역 바로 위(1pt)에 붙는다.
    static let carouselActionsBottomPadding: CGFloat = 1

    /// 화면 가운데에서 표지 한 칸만큼 멀어질수록 옆 표지 크기로 줄인다.
    static func carouselScale(midX: CGFloat, viewportWidth: CGFloat) -> CGFloat {
        let step = coverSize.width + carouselSpacing
        guard viewportWidth > 0, step > 0, midX.isFinite else { return 1 }
        let distance = min(1, abs(midX - viewportWidth / 2) / step)
        return 1 - (1 - sideCoverScale) * distance
    }
}
