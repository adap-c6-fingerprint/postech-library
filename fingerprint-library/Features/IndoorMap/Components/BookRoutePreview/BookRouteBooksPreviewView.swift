import ComposableArchitecture
import SwiftUI

/// 탭과 카드가 책 선택을 공유한다. 부모는 선택한 책 또는 전체 경로로 안내를 시작한다.
struct BookRouteBooksPreviewView: View {
    let books: [Book]
    let shelfStore: StoreOf<BookShelfMapFeature>
    let session: BookNavigationSession?
    let isLoadingRoute: Bool
    let routeError: String?
    let canStart: Bool
    let onBack: () -> Void
    let onStart: (Book) -> Void
    let onRetry: () -> Void
    /// 위치가 부정확하거나 맞지 않을 때 출발 위치를 직접 지정하게 한다.
    var onSetOriginManually: (() -> Void)?
    var guidesSelectedBook = false
    var homeAnnotations: HomeMapAnnotationsFeature.State?

    @State private var bookSelection = BookRoutePreviewSelection()
    @State private var panelHeight: CGFloat = 0
    @State private var panelPresentation = BookRoutePreviewPanelState()
    @State private var bookTabsHeight: CGFloat = 52
    // ✅ 접힌 카드와 펼친 상세가 같은 책별 상세 Store(소개·찜·장바구니)를 공유한다.
    @State private var detailStores = BookRoutePreviewDetailStores()
    // ✅ 펼친 상세 스크롤 뷰의 화면상 위치. 시스템이 붙이는 상단 안전 영역 여부와 관계없이 표지 위치를 시안에 맞춘다.
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

    // ✅ 시트를 끝까지 올린 상태에서만 펼친 상세 화면을 보여 준다. 드래그 중에는 기존 카드가 유지된다.
    private var isShowingExpandedDetail: Bool { panelPresentation.isExpanded }

    private var selectedShelves: [IndoorShelfLabel] {
        guard let bookID = selection.wrappedValue else { return [] }
        if let stop = session?.stops.first(where: { $0.book.id == bookID }) { return stop.candidateShelves }
        guard case let .loaded(holdings) = shelfStore.holdings[bookID] else { return [] }
        return BookDetailDestinationPresentation.resolve(
            holdings: holdings, map: shelfStore.map.map, labels: shelfStore.map.shelfLabels
        )?.shelves ?? []
    }

    private var selectedFloor: IndoorMapFloor? {
        let stop = session?.stops.first { $0.book.id == selection.wrappedValue }
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
                    // ✅ 펼친 상세는 화면 맨 위(상태바 영역 포함)부터 그려 스크롤한 표지가 잘리지 않게 한다.
                    expandedTopInsetOverride: 0,
                    identifierPrefix: "multiBookPreview", onCoveredHeightChange: { panelHeight = $0 }
                ) {
                    // ✅ 펼침 여부에 따라 접힌 카드 페이지와 펼친 상세 화면을 분기한다.
                    ZStack {
                        if isShowingExpandedDetail {
                            expandedDetail(
                                // ✅ 시안: 표지 윗변 = 안전 영역 + 버튼 44 + 21
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
                // ✅ 펼친 상세에서는 책 이름 탭 대신 뒤로가기·찜 버튼을 안전 영역 바로 아래에 띄운다.
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
        .modifier(SelectedBookCartPresentation(store: selectedBook.map { detailStores.store(for: $0) }))
        .accessibilityIdentifier("multiBookPreview")
    }

    // MARK: - 펼친 상세

    // ✅ 표지 캐러셀을 좌우로 넘기면 같은 선택 상태가 바뀌어 아래 정보·지도 서가도 함께 바뀐다.
    private func expandedDetail(coverTopGlobalY: CGFloat) -> some View {
        // ✅ 스크롤 콘텐츠가 시작하는 화면 위치를 빼서, 표지가 처음에 버튼 아래 21pt에 오도록 한다.
        let contentTop = expandedScrollOrigin.globalMinY + expandedScrollOrigin.safeAreaTop
        return ScrollView {
            BookExpandedDetailView(
                style: .carousel, books: books, selectedBookID: selection,
                coverTopPadding: max(0, coverTopGlobalY - contentTop),
                identifierPrefix: "multiBookPreview"
            ) { book in
                BookRoutePreviewExpandedDetails(
                    book: book,
                    holdings: shelfStore.holdings[book.id],
                    info: BookRoutePreviewBookInfo(
                        book: book, holdings: shelfStore.holdings[book.id],
                        resolutions: shelfStore.resolutions[book.id] ?? [],
                        map: shelfStore.map.map, session: session),
                    detailStore: detailStores.store(for: book),
                    onRetryHoldings: { shelfStore.send(.retryHoldingsTapped(book.id)) }
                )
                .padding(.horizontal, 16)
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
            // 소개를 맨 위로 돌린 뒤 아래로 당길 때만 시트를 접는다.
            panelPresentation.isContentAtTop = isAtTop
        }
        .onAppear { panelPresentation.isContentAtTop = true }
        .accessibilityIdentifier("multiBookPreview.expandedDetail")
    }

    private var expandedTopBar: some View {
        HStack {
            LibraryBackButton(identifier: "multiBookPreview.expandedBack", action: onBack)
            Spacer()
            if let book = selectedBook {
                favoriteButton(detailStores.store(for: book))
            }
        }
        .padding(.horizontal, 16) // ✅ 시안: 버튼은 안전 영역 바로 아래에 붙는다.
        .frame(height: 44)
        .background {
            // ✅ 버튼 뒤로 지나가는 표지 위에서도 상태바·버튼이 잘 보이도록 위쪽만 어둡게 한다.
            LinearGradient(colors: [.black.opacity(0.4), .clear], startPoint: .top, endPoint: .bottom)
                .padding(.bottom, -16)
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private func favoriteButton(_ store: StoreOf<BookDetailFeature>) -> some View {
        Button { store.send(.favoriteButtonTapped) } label: {
            Image(systemName: store.isFavorite ? "heart.fill" : "heart")
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
        .task(id: store.book.id) { store.send(.loadFavoriteStatus) }
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
        .accessibilityLabel("장바구니에 담기")
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
                .foregroundStyle(isSelected ? DS.ColorToken.neutralDark : DS.ColorToken.neutralPrimary)
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
                BookRoutePreviewBookCard(
                    book: book,
                    holdings: shelfStore.holdings[book.id],
                    resolutions: shelfStore.resolutions[book.id] ?? [],
                    map: shelfStore.map.map,
                    session: session,
                    detailStore: detailStores.store(for: book),
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
        .tabViewStyle(.page(indexDisplayMode: .never))
        .accessibilityIdentifier("multiBookPreview.pages")
    }

    private var startControls: some View {
        VStack(spacing: 8) {
            if let routeError {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(routeError).font(.caption)
                    Button("다시 시도", action: onRetry).font(.caption.bold())
                    if let onSetOriginManually {
                        Button("출발 위치 직접 설정", action: onSetOriginManually)
                            .font(.caption.bold())
                            .accessibilityIdentifier("multiBookPreview.setOrigin")
                    }
                }
                .padding(10)
                .background(.regularMaterial, in: .rect(cornerRadius: 12))
                .accessibilityIdentifier("multiBookPreview.error")
            }
            HStack(spacing: 12) { // ✅ 펼친 상세에서는 시안처럼 장바구니 버튼을 함께 보여 준다.
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
                if isShowingExpandedDetail, let book = selectedBook {
                    cartButton(detailStores.store(for: book))
                }
            }
        }
    }
}

// ✅ 펼친 상세 스크롤 뷰의 화면상 윗변과 시스템이 붙인 상단 안전 영역.
private nonisolated struct ExpandedScrollOrigin: Equatable {
    let globalMinY: CGFloat
    let safeAreaTop: CGFloat
}

// ✅ 책별 상세 Store를 책 ID로 보관한다. 페이지를 넘기거나 펼침 상태가 바뀌어도 불러온 소개·찜 상태를 유지한다.
@MainActor
final class BookRoutePreviewDetailStores {
    private var stores: [Book.ID: StoreOf<BookDetailFeature>] = [:]

    func store(for book: Book) -> StoreOf<BookDetailFeature> {
        if let store = stores[book.id] { return store }
        let store = Store(initialState: BookDetailFeature.State(book: book)) { BookDetailFeature() }
        stores[book.id] = store
        return store
    }
}

// ✅ 펼친 상세의 장바구니 버튼이 단권 상세와 같은 알림을 띄우도록 선택한 책의 Store에 연결한다.
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
