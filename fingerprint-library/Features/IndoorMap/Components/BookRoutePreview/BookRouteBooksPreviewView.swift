import ComposableArchitecture
import SwiftUI

/// 책 선택은 미리보기만 바꾼다. 안내 시작에는 부모가 보관한 전체 경로를 전달한다.
struct BookRouteBooksPreviewView: View {
    let books: [Book]
    let shelfStore: StoreOf<BookShelfMapFeature>
    let session: BookNavigationSession?
    let isLoadingRoute: Bool
    let routeError: String?
    let canStart: Bool
    let onBack: () -> Void
    let onStart: () -> Void
    let onRetry: () -> Void

    @State private var bookSelection = BookRoutePreviewSelection()
    @State private var panelHeight: CGFloat = 0
    @State private var camera: IndoorMapCameraRequest?

    private struct ShelfFocus: Equatable {
        let bookID: Book.ID?
        let featureIDs: [IndoorMapElement.ID]
        let mapSize: CGSize
        let bottomInset: CGFloat
    }

    private var selection: Binding<Book.ID?> {
        Binding(
            get: { bookSelection.bookID(in: books) },
            set: { bookSelection.select($0, in: books) }
        )
    }

    private var selectedShelves: [IndoorShelfLabel] {
        guard let bookID = selection.wrappedValue else { return [] }
        return session?.stops.first { $0.book.id == bookID }?.candidateShelves
            ?? shelfStore.state.shelves(for: bookID)
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
            let focus = ShelfFocus(
                bookID: selection.wrappedValue,
                featureIDs: visibleShelves.map(\.mapElementID),
                mapSize: geometry.size,
                bottomInset: bottomInset
            )
            ZStack(alignment: .bottom) {
                IndoorMapView(
                    store: shelfStore.scope(state: \.map, action: \.map),
                    showsDestinationCard: false, showsRoute: false,
                    bottomContentInset: bottomInset, topContentInset: 16,
                    showsCurrentLocationButton: false, showsFloorPicker: false,
                    bookDetail: .init(floor: selectedFloor, shelves: visibleShelves, cameraRequest: camera)
                )
                .ignoresSafeArea(.container)
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
            .onChange(of: focus, initial: true) { _, focus in
                guard !focus.featureIDs.isEmpty else {
                    camera = nil
                    return
                }
                camera = .init(id: (camera?.id ?? 0) + 1, target: .features(focus.featureIDs))
            }
        }
        .foregroundStyle(Color.textPrimary)
        .onChange(of: books.map(\.id)) { _, _ in
            bookSelection.reconcile(with: books)
        }
        .accessibilityIdentifier("multiBookPreview")
    }

    private var bookTabs: some View {
        HStack(spacing: 12) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 22))
                    .frame(width: 44, height: 44)
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            .accessibilityLabel("뒤로가기")
            .accessibilityIdentifier("multiBookPreview.back")

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
                .frame(height: 32)
                .foregroundStyle(isSelected ? Color.black : Color.textPrimary)
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
            Button(action: onStart) {
                HStack(spacing: 8) {
                    if isLoadingRoute { ProgressView().tint(Color.textPrimary) }
                    Text(isLoadingRoute ? "경로 확인 중" : "바로 안내 시작")
                        .typography(.bookTitle)
                }
                .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.glass(.regular.tint(Color(white: 0.08).opacity(0.6))))
            .buttonBorderShape(.capsule)
            .disabled(!canStart)
            .accessibilityHint("선택한 전체 \(books.count)권을 최적 경로 순서로 안내해요")
            .accessibilityIdentifier("multiBookPreview.start")
        }
    }
}
