import SwiftUI
import UIKit
import ComposableArchitecture

/// 추천·검색의 지도 Store를 재사용하고, 책 상세 전용 경로는 별도로 계산한다.
struct BookDetailMapView: View {
    let store: StoreOf<BookDetailFeature>
    let mapStore: StoreOf<IndoorMapFeature>
    @Environment(\.dismiss) private var dismiss
    @State private var sheetHeight: CGFloat = 0

    private var context: BookDetailMapContext {
        .init(map: mapStore.map, navigation: mapStore.navigation, labels: mapStore.shelfLabels,
              position: mapStore.currentPosition, preference: mapStore.routePreference)
    }

    var body: some View {
        GeometryReader { geometry in
            IndoorMapView(
                store: mapStore, showsDestinationCard: false, showsRoute: false,
                bottomContentInset: min(sheetHeight, geometry.size.height),
                highlightedFeatureIDs: Set(store.destinationPresentation?.shelves.map(\.mapElementID) ?? [])
            )
            .ignoresSafeArea(.container, edges: .top)
        }
        .overlay(alignment: .top) { mapButtons }
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
                store: store, onDismiss: { dismiss() }, onHeightChange: { sheetHeight = $0 }
            )
            .id(store.book.id)
        }
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
    var onHeightChange: (CGFloat) -> Void = { _ in }

    var body: some View {
        NavigationStack {
            BookDetailView(store: store)
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityVoiceOverEnabled) private var isVoiceOverEnabled
    @State private var isNoticePresented = false
    @State private var noticeMessage = ""
    @State private var isRoutePreviewPresented = false

    var body: some View {
        detailContent
            .safeAreaInset(edge: .bottom, spacing: 0) { bottomActions }
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
        if !dynamicTypeSize.isAccessibilitySize && !isVoiceOverEnabled {
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
            Text(BookText.plainText(store.book.title))
                .bookDetailTypography(.bookTitle)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityAction(named: Text(store.isFavorite ? "찜 해제" : "찜하기")) {
                    store.send(.favoriteButtonTapped)
                }
            if case .loaded = store.holdingsState {
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.destinationPresentation?.locationText
                         ?? store.displayedHolding?.locationName ?? "위치 정보 없음")
                    Text(store.displayedHolding?.callNumber ?? "청구기호 정보 없음")
                        .textSelection(.enabled)
                }
                .bookDetailTypography(.body2)
            }
            routeSummary
                .bookDetailTypography(.caption1)
                .foregroundStyle(Color.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
