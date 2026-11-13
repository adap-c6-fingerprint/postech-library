import SwiftUI

struct BookExpandedDetailView<Details: View>: View {
    enum Style {
        case single
        case carousel
    }

    let style: Style
    let books: [Book]
    @Binding var selectedBookID: Book.ID?
    var coverTopPadding: CGFloat = BookExpandedDetailLayout.coverTopPadding
    var identifierPrefix = "bookExpandedDetail"
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
            imageCornerRadius: isMultiple ? BookExpandedDetailLayout.carouselCoverCornerRadius : 0)
            .frame(width: BookExpandedDetailLayout.coverSize.width,
                   height: BookExpandedDetailLayout.coverSize.height)
        if isMultiple {
            cover.shadow(color: .black.opacity(0.3), radius: 18, y: 8)
        } else {
            cover
                .background(.quaternary)
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .shadow(color: .black.opacity(0.3), radius: 18, y: 8)
        }
    }

    @ViewBuilder
    private var coverCarousel: some View {
        let shadowInset = BookExpandedDetailLayout.carouselShadowInset
        let height = BookExpandedDetailLayout.coverSize.height + shadowInset * 2
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

nonisolated enum BookExpandedDetailLayout {
    static let coverSize = CGSize(width: 218, height: 310)
    static let coverTopPadding: CGFloat = 30
    static let detailsTopPadding: CGFloat = 24
    static let carouselSpacing: CGFloat = 8
    static let carouselShadowInset: CGFloat = 28
    static let sideCoverScale: CGFloat = 0.82
    static let indicatorTopPadding: CGFloat = 16
    static let indicatorHorizontalPadding: CGFloat = 16
    static let carouselCoverTopPadding: CGFloat = 21
    static let carouselCoverCornerRadius: CGFloat = 8
    static let carouselActionsBottomPadding: CGFloat = 1

    static func carouselScale(midX: CGFloat, viewportWidth: CGFloat) -> CGFloat {
        let step = coverSize.width + carouselSpacing
        guard viewportWidth > 0, step > 0, midX.isFinite else { return 1 }
        let distance = min(1, abs(midX - viewportWidth / 2) / step)
        return 1 - (1 - sideCoverScale) * distance
    }
}
