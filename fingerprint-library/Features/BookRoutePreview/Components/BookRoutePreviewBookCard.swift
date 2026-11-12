import ComposableArchitecture
import SwiftUI

struct BookRoutePreviewBookCard: View {
    let book: Book
    let holdings: BookShelfMapFeature.HoldingsState?
    let resolutions: [ShelfResolution]
    let map: IndoorMap?
    let routePlan: RoutePlan?
    let showsFullDescription: Bool
    let isSheetMoving: Bool
    let isSelected: Bool
    let onContentAtTopChange: (Bool) -> Void
    let onRetryHoldings: () -> Void
    let detailStore: StoreOf<BookDetailFeature>

    @State private var isContentAtTop = true
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(book: Book, holdings: BookShelfMapFeature.HoldingsState?,
         resolutions: [ShelfResolution], map: IndoorMap?,
         routePlan: RoutePlan?, detailStore: StoreOf<BookDetailFeature>,
         showsFullDescription: Bool = false,
         isSheetMoving: Bool = false, isSelected: Bool = true,
         onContentAtTopChange: @escaping (Bool) -> Void = { _ in },
         onRetryHoldings: @escaping () -> Void) {
        self.book = book
        self.holdings = holdings
        self.resolutions = resolutions
        self.map = map
        self.routePlan = routePlan
        self.showsFullDescription = showsFullDescription
        self.isSheetMoving = isSheetMoving
        self.isSelected = isSelected
        self.onContentAtTopChange = onContentAtTopChange
        self.onRetryHoldings = onRetryHoldings
        self.detailStore = detailStore
    }

    private var info: BookRoutePreviewBookInfo {
        BookRoutePreviewBookInfo(
            book: book, holdings: holdings, resolutions: resolutions, map: map, routePlan: routePlan)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                let layout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
                    : AnyLayout(HStackLayout(alignment: .top, spacing: 14))
                layout {
                    BookCoverView(
                        url: book.imageURL, isbn: book.isbn,
                        imageCornerRadius: BookExpandedDetailLayout.carouselCoverCornerRadius)
                        .frame(width: 140, height: 186)
                    bibliography
                }
                description
            }
            .padding(16)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .scrollDisabled(isSheetMoving)
        .onScrollGeometryChange(for: Bool.self) {
            $0.contentOffset.y + $0.contentInsets.top <= 1
        } action: { _, isAtTop in
            isContentAtTop = isAtTop
            if isSelected { onContentAtTopChange(isAtTop) }
        }
        .onChange(of: isSelected, initial: true) { _, selected in
            if selected { onContentAtTopChange(isContentAtTop) }
        }
        .accessibilityIdentifier("multiBookPreview.card.\(book.id)")
        .task {
            if book.description?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                detailStore.send(.loadDescription)
            }
        }
    }

    private var bibliography: some View {
        let info = self.info
        let holding = info.holding
        return VStack(alignment: .leading, spacing: 8) {
            switch holdings {
            case nil, .loading:
                ProgressView("소장 위치 확인 중").font(.caption)
            case .failed:
                Text("소장 위치 확인 실패").font(.caption)
                Button("다시 시도", action: onRetryHoldings).font(.caption)
            case .loaded:
                Text(holding?.availabilityText ?? "소장정보 없음")
                    .typography(.caption2)
                    .foregroundStyle(holding?.availability == "available" ? Color.green : Color.textTertiary)
            }
            Text(BookText.plainText(book.title))
                .typography(.bookTitle)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let location = info.location { Text(location).typography(.body2) }
            if let callNumber = holding?.callNumber {
                Text(callNumber).typography(.body2).textSelection(.enabled)
            }
            if let routeSummary = info.routeSummary {
                Text(routeSummary)
                    .typography(.caption1)
                    .foregroundStyle(Color.textTertiary)
                    .accessibilityLabel("경로 시작부터 이 책까지 \(routeSummary)")
            } else if holding != nil && info.shelves.isEmpty {
                Text("안내할 서가 위치를 확인할 수 없어요.")
                    .font(.caption).foregroundStyle(Color.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var description: some View {
        BookRoutePreviewDescription(
            book: book, detailStore: detailStore,
            style: .card(showsFullDescription: showsFullDescription))
    }
}

struct BookRoutePreviewDescription: View {
    enum Style: Equatable {
        case card(showsFullDescription: Bool)
        case expanded
    }

    let book: Book
    let detailStore: StoreOf<BookDetailFeature>
    let style: Style
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var showsFullDescription: Bool {
        if case let .card(showsFullDescription) = style { return showsFullDescription }
        return true
    }

    private var bodyTypography: PobookUI.Typography { style == .expanded ? .caption1 : .caption2 }

    var body: some View {
        VStack(alignment: .leading, spacing: style == .expanded ? 4 : 6) {
            let author = BookText.plainText(book.author).trimmingCharacters(in: .whitespacesAndNewlines)
            if !author.isEmpty { Text("\(author) 저자").typography(.body2) }
            Group {
                if let summary = book.description, !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    descriptionText(BookText.plainText(summary))
                } else if detailStore.isLoading || !detailStore.hasLoaded {
                    ProgressView("책 소개를 불러오고 있어요")
                        .typography(bodyTypography)
                } else if let message = detailStore.errorMessage {
                    Text(message)
                        .typography(bodyTypography)
                    if detailStore.isbn13 != nil {
                        Button("다시 시도") { detailStore.send(.retryButtonTapped) }
                            .typography(bodyTypography)
                    }
                } else if let description = detailStore.description {
                    descriptionText(description.text)
                } else {
                    Text("이 책의 소개가 아직 제공되지 않아요.")
                        .typography(bodyTypography)
                }
            }
            .foregroundStyle(Color.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func descriptionText(_ text: String) -> some View {
        if style == .expanded {
            Text(text)
                .typography(.caption1)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .accessibilityIdentifier("multiBookPreview.expandedDescription.\(book.id)")
        } else {
            cardDescriptionText(text)
        }
    }

    private func cardDescriptionText(_ text: String) -> some View {
        Text(text)
            .lineLimit(showsFullDescription ? nil : collapsedDescriptionLineCount)
            .truncationMode(.tail)
            .typography(.caption2)
            .frame(width: 322, height: showsFullDescription ? nil : 100.8, alignment: .topLeading)
            .fixedSize(horizontal: false, vertical: showsFullDescription)
            .accessibilityIdentifier("multiBookPreview.description.\(book.id)")
    }

    private var collapsedDescriptionLineCount: Int {
        let metrics = PobookUI.Typography.caption2.metrics(for: dynamicTypeSize)
        let lineHeight = max(metrics.lineHeight, metrics.font.lineHeight)
        return max(1, Int(((100.8 + 0.01) / lineHeight).rounded(.down)))
    }
}
