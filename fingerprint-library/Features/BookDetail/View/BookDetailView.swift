import SwiftUI
import UIKit
import ComposableArchitecture

/// 추천·검색의 지도 Store를 재사용하고, 책 상세 전용 경로는 별도로 계산한다.
struct BookDetailMapView: View {
    let store: StoreOf<BookDetailFeature>
    let mapStore: StoreOf<IndoorMapFeature>
    @Environment(\.dismiss) private var dismiss
    @State private var sheetFrame: CGRect?
    @State private var sheetPresentation = BookDetailSheetPresentation()

    private var context: BookDetailMapContext {
        .init(map: mapStore.map, navigation: mapStore.navigation, labels: mapStore.shelfLabels,
              position: mapStore.currentPosition, preference: mapStore.routePreference)
    }

    private var destinationFloor: IndoorMapFloor? {
        guard let shelves = store.destinationPresentation?.shelves,
              let floorID = shelves.first?.floorID,
              shelves.allSatisfy({ $0.floorID == floorID }) else { return nil }
        return mapStore.map?.floors.first { $0.id == floorID }
    }

    var body: some View {
        GeometryReader { geometry in
            let coveredHeight = sheetFrame.map { max(0, geometry.size.height - $0.minY) } ?? 0
            ZStack(alignment: .bottomTrailing) {
                IndoorMapView(
                    store: mapStore, showsDestinationCard: false, showsRoute: false,
                    bottomContentInset: min(coveredHeight, geometry.size.height),
                    highlightedFeatureIDs: Set(store.destinationPresentation?.shelves.map(\.mapElementID) ?? []),
                    showsFloorPicker: false
                )
                .ignoresSafeArea(.container, edges: .top)

                if !sheetPresentation.isExpanded, sheetFrame != nil, let floor = destinationFloor {
                    destinationFloorBadge(floor)
                        .padding(.trailing, 16)
                        .padding(.bottom, coveredHeight + 16)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .overlay {
            if sheetPresentation.isExpanded { BookDetailCoverBackground(book: store.book) }
        }
        .overlay(alignment: .top) {
            if !sheetPresentation.isExpanded { mapButtons }
        }
        .toolbar(.hidden, for: .navigationBar, .tabBar)
        .preferredColorScheme(.dark)
        .onChange(of: store.destinationPresentation?.shelves, initial: true) { _, shelves in
            guard let shelves, let floorID = shelves.first?.floorID,
                  shelves.allSatisfy({ $0.floorID == floorID }) else { return }
            if mapStore.selectedFloorID != floorID { mapStore.send(.floorSelected(floorID)) }
        }
        .task(id: context) { store.send(.mapContextChanged(context)) }
        .background {
            BookDetailSheetPresenter(
                store: store, presentation: sheetPresentation,
                onDismiss: { dismiss() }, onFrameChange: { sheetFrame = $0 }
            )
            .id(store.book.id)
        }
    }

    private func destinationFloorBadge(_ floor: IndoorMapFloor) -> some View {
        Text("\(floor.ordinal + 1)F")
            .bookDetailTypography(.caption2)
            .foregroundStyle(Color.textPrimary)
            .padding(.horizontal, 12)
            .frame(minWidth: 61, minHeight: 34)
            .glassEffect(.regular, in: .rect(cornerRadius: 12))
            .accessibilityLabel("책 위치 \(floor.name)")
            .accessibilityIdentifier("bookDetail.destinationFloor")
            .allowsHitTesting(false)
    }

    private var mapButtons: some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: "chevron.left").frame(width: 44, height: 44)
                    .glassEffect(.regular.interactive(), in: Circle())
            }
            .accessibilityLabel("뒤로가기")
            .accessibilityIdentifier("bookDetail.back")
            Spacer()
            Button { store.send(.favoriteButtonTapped) } label: {
                Image(systemName: store.isFavorite ? "heart.fill" : "heart")
                    .frame(width: 44, height: 44)
                    .glassEffect(.regular.interactive(), in: Circle())
            }
            .accessibilityLabel(store.isFavorite ? "찜 해제" : "찜하기")
            .accessibilityValue(store.isFavorite ? "찜됨" : "찜 안 됨")
            .accessibilityIdentifier("bookDetail.favorite")
        }
        .font(.system(size: 22, weight: .regular))
        .buttonStyle(.plain)
        .foregroundStyle(Color.textPrimary)
        .buttonBorderShape(.circle)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .background { Color.clear }
    }
}

struct BookDetailSheet: View {
    let store: StoreOf<BookDetailFeature>
    let presentation: BookDetailSheetPresentation
    var onDismiss: () -> Void
    var onHeightChange: (CGFloat) -> Void = { _ in }

    var body: some View {
        NavigationStack {
            BookDetailView(store: store, isExpanded: presentation.isExpanded, onDismiss: onDismiss)
                .containerBackground(.clear, for: .navigation)
                .toolbar(.hidden, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .onGeometryChange(for: CGFloat.self) { $0.size.height + $0.safeAreaInsets.bottom } action: { height in
            guard height.isFinite, height > 0 else { return }
            onHeightChange(height)
        }
    }
}

struct BookDetailView: View {
    @Bindable var store: StoreOf<BookDetailFeature>
    var isExpanded = false
    var onDismiss: () -> Void = { }
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityVoiceOverEnabled) private var isVoiceOverEnabled
    @State private var isNoticePresented = false
    @State private var noticeMessage = ""
    @State private var isRoutePreviewPresented = false

    var body: some View {
        detailContent
            .safeAreaInset(edge: .top, spacing: 0) {
                if isExpanded { expandedTopBar }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { bottomActions }
            .background {
                if isExpanded { BookDetailCoverBackground(book: store.book) }
            }
            .foregroundStyle(Color.textPrimary)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .alert("도서 안내", isPresented: $isNoticePresented) {
                Button("확인", role: .cancel) { }
            } message: { Text(noticeMessage) }
            .navigationDestination(item: $store.scope(state: \.shelfMap, action: \.shelfMap)) {
                BookShelfMapView(store: $0).toolbar(.visible, for: .navigationBar)
            }
            .fullScreenCover(isPresented: $isRoutePreviewPresented) {
                BookRoutePreviewView(books: [store.book])
            }
            .basketLimitAlert(isPresented: store.isBasketLimitAlertPresented) {
                store.send(.basketLimitAlertDismissed)
            }
            .task { store.send(.loadFavorites) }
            .task { store.send(.loadHoldings) }
            .task { store.send(.loadDescription) }
            .task { store.send(.loadRelatedBooks) }
    }

    @ViewBuilder
    private var detailContent: some View {
        if isExpanded {
            expandedContent
        } else if !dynamicTypeSize.isAccessibilitySize && !isVoiceOverEnabled {
            VStack(alignment: .leading, spacing: 36) {
                header
                    .padding(.horizontal, 16)
                    .padding(.top, 20)
                ScrollView {
                    descriptionSection.padding(.horizontal, 16).padding(.bottom, 20)
                }
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 36) { header; descriptionSection }
                    .padding(.horizontal, 16).padding(.top, 20).padding(.bottom, 20)
            }
        }
    }

    private var expandedContent: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    BookCoverView(url: store.book.imageURL, isbn: store.book.isbn)
                        .frame(width: min(218, geometry.size.width * 0.55), height: 310)
                        .background(.quaternary)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                        .shadow(color: .black.opacity(0.3), radius: 18, y: 8)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 30)
                        .padding(.bottom, 32)
                        .accessibilityIdentifier("bookDetail.expandedCover")
                    VStack(alignment: .leading, spacing: 8) {
                        holdingStatus.bookDetailTypography(.caption2)
                        bookTitle
                            .lineLimit(dynamicTypeSize.isAccessibilitySize || isVoiceOverEnabled ? nil : 2)
                            .truncationMode(.tail)
                        holdingLocation
                        expandedRouteSummary
                    }
                    descriptionSection.padding(.top, 24)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
            .accessibilityIdentifier("bookDetail.expandedContent")
        }
    }

    private var expandedTopBar: some View {
        HStack {
            Button(action: onDismiss) {
                Image(systemName: "chevron.left").frame(width: 44, height: 44)
                    .glassEffect(.regular.interactive(), in: Circle())
            }
            .accessibilityLabel("뒤로가기")
            .accessibilityIdentifier("bookDetail.expandedBack")
            Spacer()
            Button { store.send(.favoriteButtonTapped) } label: {
                Image(systemName: store.isFavorite ? "heart.fill" : "heart")
                    .frame(width: 44, height: 44)
                    .glassEffect(.regular.interactive(), in: Circle())
            }
            .accessibilityLabel(store.isFavorite ? "찜 해제" : "찜하기")
            .accessibilityValue(store.isFavorite ? "찜됨" : "찜 안 됨")
            .accessibilityIdentifier("bookDetail.expandedFavorite")
        }
        .font(.system(size: 22, weight: .regular))
        .buttonStyle(.plain)
        .buttonBorderShape(.circle)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var header: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 16) { cover; bibliography }
        } else {
            HStack(alignment: .top, spacing: 14) {
                cover
                bibliography
            }
        }
    }

    private var cover: some View {
        BookCoverView(url: store.book.imageURL, isbn: store.book.isbn)
            .frame(width: 140, height: 186)
            .background(.quaternary)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .accessibilityIdentifier("bookDetail.cover")
    }

    private var bibliography: some View {
        VStack(alignment: .leading, spacing: 8) {
            holdingStatus
                .bookDetailTypography(.caption2)
            bookTitle
            holdingLocation
            routeSummary
                .bookDetailTypography(.caption1)
                .foregroundStyle(Color.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var bookTitle: some View {
        Text(BookText.plainText(store.book.title))
            .bookDetailTypography(.bookTitle)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
            .accessibilityAction(named: Text(store.isFavorite ? "찜 해제" : "찜하기")) {
                store.send(.favoriteButtonTapped)
            }
    }

    @ViewBuilder
    private var holdingLocation: some View {
        if case .loaded = store.holdingsState {
            VStack(alignment: .leading, spacing: 2) {
                Text(store.destinationPresentation?.locationText
                     ?? store.displayedHolding?.locationName ?? "위치 정보 없음")
                Text(store.displayedHolding?.callNumber ?? "청구기호 정보 없음")
                    .textSelection(.enabled)
            }
            .bookDetailTypography(.body2)
        }
    }

    @ViewBuilder
    private var holdingStatus: some View {
        switch store.holdingsState {
        case .idle, .loading: ProgressView("소장정보 확인 중")
        case .loaded:
            if let holding = store.displayedHolding {
                Text(holding.availabilityText)
                    .foregroundStyle(holding.availability == "available" ? Color.green : Color.textTertiary)
            } else { Text("소장정보 없음").foregroundStyle(Color.textTertiary) }
        case .failed:
            VStack(alignment: .leading, spacing: 4) {
                Text("소장정보를 불러오지 못했어요.")
                Button("다시 시도") { store.send(.retryHoldingsButtonTapped) }
            }
        }
    }

    @ViewBuilder
    private var routeSummary: some View {
        switch store.destinationRouteState {
        case .idle: Text("거리 확인 중")
        case .loading: ProgressView("거리 확인 중")
        case .unavailable: Text("거리 확인 불가")
        case .loaded(let summary): Text(summary.text)
        }
    }

    private var expandedRouteSummary: some View {
        HStack(spacing: 16) {
            Spacer(minLength: 0)
            if case let .loaded(summary) = store.destinationRouteState {
                HStack(spacing: 6) {
                    routeIcon("figure.walk", color: Color(white: 0.45))
                    Text("\(summary.isEstimated ? "약 " : "")\(summary.distanceMeters)m")
                }
                HStack(spacing: 6) {
                    routeIcon("figure.stairs", color: .green)
                    Text("\(summary.floorChangeCount)회")
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("층 이동 \(summary.floorChangeCount)회")
            } else {
                routeSummary
            }
        }
        .bookDetailTypography(.caption1)
        .foregroundStyle(Color.textSecondary)
        .padding(.top, 2)
    }

    private func routeIcon(_ name: String, color: Color) -> some View {
        Image(systemName: name)
            .font(.system(size: 18, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: 28, height: 28)
            .background(color, in: Circle())
            .accessibilityHidden(true)
    }

    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            let author = BookText.plainText(store.book.author).trimmingCharacters(in: .whitespacesAndNewlines)
            if !author.isEmpty {
                Text("\(author) 저자").bookDetailTypography(.body2)
            }
            descriptionContent
                .bookDetailTypography(.caption1)
                .foregroundStyle(Color.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var descriptionContent: some View {
        if store.isLoading || !store.hasLoaded {
            ProgressView("책 정보를 불러오고 있어요").frame(maxWidth: .infinity, minHeight: 80)
        } else if let message = store.errorMessage {
            VStack(alignment: .leading, spacing: 12) {
                Label(message, systemImage: "exclamationmark.circle")
                if store.isbn13 != nil {
                    Button("다시 시도") { store.send(.retryButtonTapped) }.buttonStyle(.bordered)
                }
            }
        } else if let description = store.description {
            Text(description.text).textSelection(.enabled)
            Link(destination: description.sourceURL) {
                Label("책 소개 제공: Yes24 · 원문 보기", systemImage: "arrow.up.right.square")
                    .font(.footnote)
            }
            .padding(.top, 8)
        } else { Text("이 책의 정보가 아직 제공되지 않아요.") }
    }

    private var bottomActions: some View {
        HStack(spacing: 12) {
            Button { isRoutePreviewPresented = true } label: {
                Text("바로 안내 시작").bookDetailTypography(.bookTitle).frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
            .buttonSizing(.flexible)
            .controlSize(.large)
            .frame(maxWidth: .infinity, minHeight: 50)
            .accessibilityIdentifier("bookDetail.startGuidance")
            Button {
                store.send(.addToBasketButtonTapped)
                if !store.isBasketLimitAlertPresented {
                    noticeMessage = "책바구니에서 이 책을 확인할 수 있어요."
                    isNoticePresented = true
                }
            } label: { Image(systemName: "cart.fill").font(.system(size: 23, weight: .semibold)) }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .controlSize(.large)
            .frame(width: 50, height: 50)
            .accessibilityLabel("장바구니에 담기")
            .accessibilityIdentifier("bookDetail.addToBasket")
        }
        .foregroundStyle(Color.textPrimary)
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .background {
            LinearGradient(colors: [.clear, .black.opacity(0.25)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(.container, edges: .bottom)
        }
    }
}

private struct BookDetailCoverBackground: View {
    let book: Book

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                Color(white: 0.06)
                BookCoverView(url: book.imageURL, isbn: book.isbn, allowsRetry: false)
                    .frame(width: geometry.size.width, height: geometry.size.height * 0.7)
                    .scaleEffect(1.8)
                    .blur(radius: 60)
                LinearGradient(stops: [
                    .init(color: .black.opacity(0.35), location: 0),
                    .init(color: .black.opacity(0.45), location: 0.3),
                    .init(color: Color(white: 0.06), location: 0.65),
                    .init(color: Color(white: 0.06), location: 1)
                ], startPoint: .top, endPoint: .bottom)
            }
            .clipped()
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// 디자인 시스템의 글꼴·간격을 사용하면서 접근성 글자 크기에 대응한다.
private extension View {
    func bookDetailTypography(_ style: DS.Typography) -> some View {
        let fontLineHeight = UIFont(name: style.fontName, size: style.size)?.lineHeight ?? style.lineHeight
        let extraSpacing = max(0, style.lineHeight - fontLineHeight)
        return font(.custom(style.fontName, size: style.size, relativeTo: .body))
            .tracking(style.letterSpacing)
            .lineSpacing(extraSpacing)
            .padding(.vertical, extraSpacing / 2)
    }
}
