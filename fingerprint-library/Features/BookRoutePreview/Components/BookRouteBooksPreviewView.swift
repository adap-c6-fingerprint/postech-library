import ComposableArchitecture
import SwiftUI

struct BookRouteBooksPreviewView: View {
    let books: [Book]
    let shelfStore: StoreOf<BookShelfMapFeature>
    let routePlan: RoutePlan?
    let isLoadingRoute: Bool
    let routeError: String?
    var startNotice: String? = nil
    let canStart: Bool
    let onBack: () -> Void
    let onStart: (Book) -> Void
    let onRetry: () -> Void
    var onSetOriginManually: (() -> Void)?
    var guidesSelectedBook = false
    var homeAnnotations: HomeMapAnnotationsFeature.State?

    @State private var bookSelection = BookRoutePreviewSelection()
    @State private var panelHeight: CGFloat = 0
    @State private var panelPresentation = BookRoutePreviewPanelState()
    @State private var bookTabsHeight: CGFloat = 52
    @State private var expandedScrollOrigin = ExpandedScrollOrigin(globalMinY: 0, safeAreaTop: 0)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var selection: Binding<Book.ID?> {
        Binding(
            get: { bookSelection.bookID(in: books) },
            set: { bookSelection.select($0, in: books) }
        )
    }

    private var selectedBook: Book? {
        books.first { $0.id == selection.wrappedValue }
    }

    private var isShowingExpandedDetail: Bool { panelPresentation.isExpanded }

    private func detailStore(for book: Book) -> StoreOf<BookDetailFeature>? {
        shelfStore.scope(state: \.details[id: book.id], action: \.details[id: book.id])
    }

    private var selectedShelves: [IndoorShelfLabel] {
        guard let bookID = selection.wrappedValue else { return [] }
        if let stop = routePlan?.stops.first(where: { $0.book.id == bookID }) { return stop.candidateShelves }
        guard case let .loaded(holdings) = shelfStore.holdings[bookID] else { return [] }
        return BookDetailDestinationPresentation.resolve(
            holdings: holdings, map: shelfStore.map.map, labels: shelfStore.map.shelfLabels
        )?.shelves ?? []
    }

    private var selectedFloor: IndoorMapFloor? {
        let stop = routePlan?.stops.first { $0.book.id == selection.wrappedValue }
        guard let floorID = stop?.shelf.floorID ?? selectedShelves.first?.floorID else { return nil }
        return shelfStore.map.map?.floors.first { $0.id == floorID }
    }

    var body: some View {
        GeometryReader { geometry in
            let visibleShelves = selectedShelves.filter { $0.floorID == selectedFloor?.id }
            let bottomInset = panelHeight + geometry.safeAreaInsets.bottom
            ZStack(alignment: .bottom) {
                BookDetailShelfMapView(
                    store: shelfStore.scope(state: \.map, action: \.map),
                    floor: selectedFloor, shelves: visibleShelves,
                    mapSize: geometry.size, bottomContentInset: bottomInset,
                    isReadyToFocus: panelHeight > 0, homeAnnotations: homeAnnotations,
                    hiddenFavoriteMarkerIDs: Set([shelfStore.sourceFavoriteMarkerID].compactMap { $0 })
                )
                .accessibilityIdentifier("multiBookPreview.map")
                .allowsHitTesting(!panelPresentation.isExpanded)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .overlay(alignment: .bottom) {
                BookPreviewSheet(
                    presentation: $panelPresentation, floor: selectedFloor,
                    availableSize: BookPreviewSheetLayout.fullSize(
                        contentSize: geometry.size, top: geometry.safeAreaInsets.top,
                        bottom: geometry.safeAreaInsets.bottom, leading: geometry.safeAreaInsets.leading,
                        trailing: geometry.safeAreaInsets.trailing),
                    safeAreaInsets: geometry.safeAreaInsets, topBarHeight: bookTabsHeight,
                    expandedBottomPadding: BookExpandedDetailLayout.carouselActionsBottomPadding,
                    expandedTopInsetOverride: 0,
                    identifierPrefix: "multiBookPreview", onCoveredHeightChange: { panelHeight = $0 }
                ) {
                    ZStack {
                        if isShowingExpandedDetail {
                            expandedDetail(
                                coverTopGlobalY: geometry.frame(in: .global).minY + 44
                                    + BookExpandedDetailLayout.carouselCoverTopPadding
                            )
                            .transition(.opacity)
                        } else {
                            bookPages.transition(.opacity)
                        }
                    }
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: isShowingExpandedDetail)
                } actions: {
                    startControls
                } expandedBackground: {
                    if let book = books.first(where: { $0.id == selection.wrappedValue }) {
                        BookPreviewCoverBackground(book: book)
                    } else {
                        Color(white: 0.06)
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .bottom)
                .offset(x: (geometry.safeAreaInsets.trailing - geometry.safeAreaInsets.leading) / 2,
                        y: geometry.safeAreaInsets.bottom)
            }
            .overlay(alignment: .top) {
                if isShowingExpandedDetail {
                    expandedTopBar
                } else {
                    bookTabs
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { bookTabsHeight = $0 }
                }
            }
        }
        .foregroundStyle(Color.textPrimary)
        .onChange(of: books.map(\.id)) { _, _ in
            bookSelection.reconcile(with: books)
        }
        .modifier(SelectedBookCartPresentation(store: selectedBook.flatMap(detailStore(for:))))
        .accessibilityIdentifier("multiBookPreview")
    }

    private func expandedDetail(coverTopGlobalY: CGFloat) -> some View {
        let contentTop = expandedScrollOrigin.globalMinY + expandedScrollOrigin.safeAreaTop
        return ScrollView {
            BookExpandedDetailView(
                style: .carousel, books: books, selectedBookID: selection,
                coverTopPadding: max(0, coverTopGlobalY - contentTop),
                identifierPrefix: "multiBookPreview"
            ) { book in
                if let detailStore = detailStore(for: book) {
                BookRoutePreviewExpandedDetails(
                    book: book,
                    holdings: shelfStore.holdings[book.id],
                    info: BookRoutePreviewBookInfo(
                        book: book, holdings: shelfStore.holdings[book.id],
                        resolutions: shelfStore.resolutions[book.id] ?? [],
                        map: shelfStore.map.map, routePlan: routePlan),
                    detailStore: detailStore,
                    onRetryHoldings: { shelfStore.send(.retryHoldingsTapped(book.id)) }
                )
                .padding(.horizontal, 16)
                }
            }
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .scrollDisabled(panelPresentation.isMoving)
        .onGeometryChange(for: ExpandedScrollOrigin.self) { proxy in
            ExpandedScrollOrigin(globalMinY: proxy.frame(in: .global).minY, safeAreaTop: proxy.safeAreaInsets.top)
        } action: { expandedScrollOrigin = $0 }
        .onScrollGeometryChange(for: Bool.self) {
            $0.contentOffset.y + $0.contentInsets.top <= 1
        } action: { _, isAtTop in
            panelPresentation.isContentAtTop = isAtTop
        }
        .onAppear { panelPresentation.isContentAtTop = true }
        .accessibilityIdentifier("multiBookPreview.expandedDetail")
    }

    private var expandedTopBar: some View {
        HStack {
            LibraryBackButton(identifier: "multiBookPreview.expandedBack", action: onBack)
            Spacer()
            if let book = selectedBook, let store = detailStore(for: book) {
                favoriteButton(store)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .background {
            LinearGradient(colors: [.black.opacity(0.4), .clear], startPoint: .top, endPoint: .bottom)
                .padding(.bottom, -16)
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private func favoriteButton(_ store: StoreOf<BookDetailFeature>) -> some View {
        Button { store.send(.favoriteButtonTapped) } label: {
            Image(systemName: store.isFavorite ? "bookmark.fill" : "bookmark")
                .font(.system(size: 22, weight: .regular))
                .frame(width: 44, height: 44)
                .glassEffect(.regular.interactive(), in: Circle())
        }
        .buttonStyle(.plain)
        .buttonBorderShape(.circle)
        .foregroundStyle(Color.textPrimary)
        .accessibilityLabel(store.isFavorite ? "찜 해제" : "찜하기")
        .accessibilityValue(store.isFavorite ? "찜됨" : "찜 안 됨")
        .accessibilityIdentifier("multiBookPreview.expandedFavorite")
    }

    private func cartButton(_ store: StoreOf<BookDetailFeature>) -> some View {
        Button { store.send(.addToCartButtonTapped) } label: {
            Image(systemName: "cart.fill").font(.system(size: 23, weight: .semibold))
        }
        .buttonStyle(.glass(.regular.tint(Color(white: 0.08).opacity(0.6))))
        .buttonBorderShape(.circle)
        .controlSize(.large)
        .frame(width: 50, height: 50)
        .foregroundStyle(Color.textPrimary)
        .accessibilityLabel("책바구니에 담기")
        .accessibilityIdentifier("multiBookPreview.addToCart")
    }

    private var bookTabs: some View {
        HStack(spacing: 12) {
            LibraryBackButton(identifier: "multiBookPreview.back", action: onBack)

            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    HStack(spacing: 12) {
                        ForEach(books) { book in
                            bookTab(book)
                                .id(book.id)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .scrollIndicators(.hidden)
                .onChange(of: selection.wrappedValue, initial: true) { _, id in
                    guard let id else { return }
                    withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(id, anchor: .center) }
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.leading, 16)
        .padding(.trailing, 12)
        .padding(.top, 8)
    }

    private func bookTab(_ book: Book) -> some View {
        let isSelected = selection.wrappedValue == book.id
        return Button {
            withAnimation(.easeInOut(duration: 0.25)) { selection.wrappedValue = book.id }
        } label: {
            Text(BookText.plainText(book.title))
                .typography(.caption1)
                .lineLimit(1)
                .padding(.horizontal, 16)
                .frame(maxWidth: 114)
                .frame(minHeight: 32)
                .foregroundStyle(isSelected ? PobookUI.ColorToken.neutralDark : PobookUI.ColorToken.neutralPrimary)
                .background(isSelected ? Color.limeBase : .clear, in: .capsule)
                .glassEffect(.regular.interactive(), in: .capsule)
        }
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityLabel(BookText.plainText(book.title))
        .accessibilityHint("이 책의 서가 위치 미리보기")
        .accessibilityIdentifier("multiBookPreview.tab.\(book.id)")
    }

    private var bookPages: some View {
        TabView(selection: selection) {
            ForEach(books) { book in
                if let detailStore = detailStore(for: book) {
                BookRoutePreviewBookCard(
                    book: book,
                    holdings: shelfStore.holdings[book.id],
                    resolutions: shelfStore.resolutions[book.id] ?? [],
                    map: shelfStore.map.map,
                    routePlan: routePlan,
                    detailStore: detailStore,
                    showsFullDescription: panelPresentation.showsFullDescription,
                    isSheetMoving: panelPresentation.isMoving,
                    isSelected: selection.wrappedValue == book.id,
                    onContentAtTopChange: { isAtTop in
                        guard selection.wrappedValue == book.id else { return }
                        panelPresentation.isContentAtTop = isAtTop
                    },
                    onRetryHoldings: { shelfStore.send(.retryHoldingsTapped(book.id)) }
                )
                .tag(Optional(book.id))
                }
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .accessibilityIdentifier("multiBookPreview.pages")
    }

    private var startControls: some View {
        VStack(spacing: 8) {
            if let startNotice {
                VStack(alignment: .leading, spacing: 8) {
                    RouteStartNoticeView(notice: startNotice)
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                    if let onSetOriginManually {
                        Button("출발 위치 직접 설정", action: onSetOriginManually)
                            .font(.caption.bold())
                            .accessibilityIdentifier("multiBookPreview.setOrigin")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("multiBookPreview.startNotice")
            }
            if let routeError {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(routeError).font(.caption)
                    Button("다시 시도", action: onRetry).font(.caption.bold())
                    if startNotice == nil, let onSetOriginManually {
                        Button("출발 위치 직접 설정", action: onSetOriginManually)
                            .font(.caption.bold())
                            .accessibilityIdentifier("multiBookPreview.setOrigin")
                    }
                }
                .padding(10)
                .background(.regularMaterial, in: .rect(cornerRadius: 12))
                .accessibilityIdentifier("multiBookPreview.error")
            }
            HStack(spacing: 12) {
                Button {
                    guard let book = books.first(where: { $0.id == selection.wrappedValue }) else { return }
                    onStart(book)
                } label: {
                    HStack(spacing: 8) {
                        if isLoadingRoute { ProgressView().tint(Color.textPrimary) }
                        Text(isLoadingRoute ? "경로 확인 중" : "바로 안내 시작")
                            .typography(.button)
                    }
                    .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.glass(.regular.tint(Color(white: 0.08).opacity(0.6))))
                .buttonBorderShape(.capsule)
                .disabled(!canStart || selection.wrappedValue == nil)
                .accessibilityHint(guidesSelectedBook
                    ? "현재 보고 있는 책의 서가로 안내해요"
                    : "선택한 전체 \(books.count)권을 최적 경로 순서로 안내해요")
                .accessibilityIdentifier("multiBookPreview.start")
                if isShowingExpandedDetail, let book = selectedBook, let store = detailStore(for: book) {
                    cartButton(store)
                }
            }
        }
    }
}

private nonisolated struct ExpandedScrollOrigin: Equatable {
    let globalMinY: CGFloat
    let safeAreaTop: CGFloat
}

private struct SelectedBookCartPresentation: ViewModifier {
    let store: StoreOf<BookDetailFeature>?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let store {
            content.bookDetailCartPresentation(store: store)
        } else {
            content
        }
    }
}

nonisolated struct BookRoutePreviewSelection: Equatable {
    private(set) var selectedBookID: Book.ID?

    func bookID(in books: [Book]) -> Book.ID? {
        if let selectedBookID, books.contains(where: { $0.id == selectedBookID }) {
            return selectedBookID
        }
        return books.first?.id
    }

    mutating func select(_ bookID: Book.ID?, in books: [Book]) {
        guard let bookID, books.contains(where: { $0.id == bookID }) else { return }
        selectedBookID = bookID
    }

    mutating func reconcile(with books: [Book]) {
        if let selectedBookID, !books.contains(where: { $0.id == selectedBookID }) {
            self.selectedBookID = nil
        }
    }
}
