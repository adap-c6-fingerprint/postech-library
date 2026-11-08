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
    var guidesSelectedBook = false
    var homeAnnotations: HomeMapAnnotationsFeature.State?

    @State private var bookSelection = BookRoutePreviewSelection()
    @State private var panelHeight: CGFloat = 0

    private var selection: Binding<Book.ID?> {
        Binding(
            get: { bookSelection.bookID(in: books) },
            set: { bookSelection.select($0, in: books) }
        )
    }

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

                VStack(spacing: 12) {
                    if let floor = selectedFloor {
                        IndoorMapFloorBadge(floor: floor)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .accessibilityLabel("책 위치 \(floor.name)")
                            .accessibilityIdentifier("multiBookPreview.floor")
                            .padding(.bottom, 4)
                    }
                    bookPages
                        .frame(height: min(360, max(160, geometry.size.height * 0.46)))
                        .glassEffect(.regular, in: .rect(cornerRadius: 28))
                    startControls
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { panelHeight = $0 }
            }
            .overlay(alignment: .top) { bookTabs }
        }
        .foregroundStyle(Color.textPrimary)
        .onChange(of: books.map(\.id)) { _, _ in
            bookSelection.reconcile(with: books)
        }
        .accessibilityIdentifier("multiBookPreview")
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
                    onRetryHoldings: { shelfStore.send(.retryHoldingsTapped(book.id)) }
                )
                .tag(Optional(book.id))
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .clipShape(.rect(cornerRadius: 28))
        .accessibilityIdentifier("multiBookPreview.pages")
    }

    private var startControls: some View {
        VStack(spacing: 8) {
            if let routeError {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(routeError).font(.caption)
                    Button("다시 시도", action: onRetry).font(.caption.bold())
                }
                .padding(10)
                .background(.regularMaterial, in: .rect(cornerRadius: 12))
                .accessibilityIdentifier("multiBookPreview.error")
            }
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
        }
    }
}
