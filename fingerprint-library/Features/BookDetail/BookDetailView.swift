import SwiftUI
import ComposableArchitecture

/// 추천 탭에서 진입하는 지도 중심 책 상세 화면
/// 지도 로딩과 위치 스트림은 AppFeature가 소유한 기존 Store를 재사용
struct BookDetailMapView: View {
    let store: StoreOf<BookDetailFeature>
    let mapStore: StoreOf<IndoorMapFeature>

    @Environment(\.dismiss) private var dismiss
    @State private var isSheetPresented = false
    @State private var isVisible = false
    @State private var sheetHeight: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            IndoorMapView(
                store: mapStore,
                showsDestinationCard: false,
                showsRoute: false,
                bottomContentInset: min(sheetHeight, geometry.size.height)
            )
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .onAppear {
            isVisible = true
            isSheetPresented = true
        }
        .onDisappear { isVisible = false }
        .sheet(isPresented: $isSheetPresented, onDismiss: {
            if isVisible { dismiss() }
        }) {
            BookDetailSheet(store: store)
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                    sheetHeight = height
                }
        }
    }
}

struct BookDetailSheet: View {
    let store: StoreOf<BookDetailFeature>
    @State private var selectedDetent: PresentationDetent = .medium

    var body: some View {
        NavigationStack {
            BookDetailView(store: store)
                .toolbar(.hidden, for: .navigationBar)
        }
        .presentationDetents([.medium, .large], selection: $selectedDetent)
        .presentationDragIndicator(.visible)
    }
}

struct BookDetailView: View {
    let store: StoreOf<BookDetailFeature>
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var isNoticePresented = false
    @State private var noticeMessage = ""

    var body: some View {
        GeometryReader { geometry in
            detailContent
                .toolbar(.visible, for: .bottomBar)
                .toolbarBackgroundVisibility(.hidden, for: .bottomBar)
                .toolbar {
                    bottomToolbar(width: max(0, geometry.size.width - 32))
                }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .alert("도서 안내", isPresented: $isNoticePresented) {
            Button("확인", role: .cancel) { }
        } message: {
            Text(noticeMessage)
        }
        .task { store.send(.loadFavorites) }
        .task { await store.send(.loadHoldings).finish() }
        .task { await store.send(.loadDescription).finish() }
        .task { await store.send(.loadRelatedBooks).finish() }
    }

    private var detailContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                routeSummaryContent

                VStack(alignment: .leading, spacing: 12) {
                    descriptionContent
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ToolbarContentBuilder
    private func bottomToolbar(width: CGFloat) -> some ToolbarContent {
        if #available(iOS 27.0, *) {
            bottomToolbarItem(width: width)
                .contentMarginsRemoved()
        } else {
            bottomToolbarItem(width: width)
        }
    }

    private func bottomToolbarItem(width: CGFloat) -> some ToolbarContent {
        ToolbarItem(placement: .bottomBar) {
            HStack(spacing: 12) {
                Button {
                    noticeMessage = "도서의 서가 위치가 연결되면 안내를 시작할 수 있어요."
                    isNoticePresented = true
                } label: {
                    Text("바로 안내 시작")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .buttonSizing(.flexible)
                .controlSize(.large)
                .frame(maxWidth: .infinity, minHeight: 50)
                .accessibilityIdentifier("bookDetail.startGuidance")

                Button {
                    store.send(.addToBasketButtonTapped)
                    noticeMessage = "검색 탭의 장바구니에서 이 책을 확인할 수 있어요."
                    isNoticePresented = true
                } label: {
                    Image(systemName: "cart.fill")
                        .font(.system(size: 23, weight: .semibold))
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .controlSize(.large)
                .frame(width: 50, height: 50)
                .accessibilityLabel("장바구니에 담기")
                .accessibilityIdentifier("bookDetail.addToBasket")
            }
            .foregroundStyle(.white)
            .frame(width: width)
        }
        .sharedBackgroundVisibility(.hidden)
    }

    @ViewBuilder
    private var header: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 16) {
                cover
                bibliography
            }
        } else {
            HStack(alignment: .top, spacing: 16) {
                cover
                bibliography
            }
        }
    }

    private var cover: some View {
        BookCoverView(url: store.book.imageURL)
            .frame(width: 100, height: 148)
            .background(.quaternary)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var bibliography: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(BookText.plainText(store.book.title))
                .font(.title3.bold())
                .fixedSize(horizontal: false, vertical: true)

            holdingContent
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var holdingContent: some View {
        if case let .loaded(holding) = store.holdingsState {
            Text(holding?.callNumber ?? "정보 없음")
                .font(.subheadline)
                .textSelection(.enabled)
        }

        HStack(spacing: 8) {
            holdingStatusContent
            Spacer(minLength: 8)
            favoriteButton
        }
    }

    @ViewBuilder
    private var holdingStatusContent: some View {
        switch store.holdingsState {
        case .idle, .loading:
            ProgressView("소장정보 확인 중")
                .font(.caption)
        case let .loaded(holding):
            availabilityLabel(holding?.availability ?? .unknown)
        case .failed:
            VStack(alignment: .leading, spacing: 4) {
                Text("소장정보를 불러오지 못했어요.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("다시 시도") { store.send(.retryHoldingsButtonTapped) }
                    .font(.caption)
            }
        }
    }

    private var favoriteButton: some View {
        Button {
            store.send(.favoriteButtonTapped)
        } label: {
            Image(systemName: store.isFavorite ? "heart.fill" : "heart")
                .font(.system(size: 20))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(store.isFavorite ? Color.red : Color.secondary)
        .accessibilityLabel(store.isFavorite ? "찜 해제" : "찜하기")
        .accessibilityValue(store.isFavorite ? "찜됨" : "찜 안 됨")
        .accessibilityIdentifier("bookDetail.favorite")
    }

    private func availabilityLabel(_ availability: BookHolding.Availability) -> some View {
        let title: String
        let color: Color
        switch availability {
        case .available:
            title = "대출 가능"
            color = .green
        case .unavailable:
            title = "대출 불가능"
            color = .secondary
        case .unknown:
            title = "대출 상태 확인 불가"
            color = .secondary
        }
        return Text(title)
            .font(.subheadline.bold())
            .foregroundStyle(color)
    }

    private var routeSummaryContent: some View {
        BookRouteSummaryView(summary: store.routeSummary)
            .accessibilityIdentifier("bookDetail.routeSummary")
    }

    @ViewBuilder
    private var descriptionContent: some View {
        if store.isLoading || !store.hasLoaded {
            ProgressView("책 정보를 불러오고 있어요")
                .frame(maxWidth: .infinity, minHeight: 80)
        } else if let message = store.errorMessage {
            VStack(alignment: .leading, spacing: 12) {
                Label(message, systemImage: "exclamationmark.circle")
                    .foregroundStyle(.secondary)
                if store.isbn13 != nil {
                    Button("다시 시도") { store.send(.retryButtonTapped) }
                        .buttonStyle(.bordered)
                }
            }
        } else if let description = store.description {
            Text(description.text)
                .textSelection(.enabled)
            Link(destination: description.sourceURL) {
                Label("책 소개 제공: Yes24 · 원문 보기", systemImage: "arrow.up.right.square")
                    .font(.footnote)
            }
        } else {
            Text("이 책의 정보가 아직 제공되지 않아요.")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var relatedBooksContent: some View {
        switch store.relatedBooksState {
        case .idle:
            Text("연관 도서 조회를 기다리고 있어요.")
                .foregroundStyle(.secondary)

        case .loading:
            ProgressView("연관 도서를 불러오고 있어요.")

        case let .loaded(books):
            if books.isEmpty {
                Text("연관 도서가 아직 없어요.")
                    .foregroundStyle(.secondary)
            } else {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(books) { book in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(BookText.plainText(book.title))
                                .font(.headline)
                            Text(BookText.plainText(book.author))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

        case let .failed(message):
            VStack(alignment: .leading, spacing: 12) {
                Text(message)
                    .foregroundStyle(.secondary)
                Button("다시 시도") {
                    store.send(.retryRelatedBooksButtonTapped)
                }
                .buttonStyle(.bordered)
            }
        }
    }
}


/// 도보·단계·거리의 값과 단위를 같은 기준선에 표시한다.
private struct BookRouteSummaryView: View {
    let summary: BookRouteSummary
    @ScaledMetric(relativeTo: .largeTitle) private var valueFontSize: CGFloat = 32

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 24) {
                metrics
            }
            .fixedSize(horizontal: true, vertical: false)

            VStack(alignment: .leading, spacing: 16) {
                metrics
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var metrics: some View {
        metric("도보", value: summary.walkingMinutes, unit: "min", spokenUnit: "분")
        metric("단계", value: summary.stepCount, unit: "steps", spokenUnit: "단계")
        metric("거리", value: summary.distanceMeters, unit: "m", spokenUnit: "미터")
    }

    private func metric(_ title: String, value: Int, unit: String, spokenUnit: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(value)")
                    .font(.system(size: valueFontSize, weight: .semibold))
                    .monospacedDigit()

                Text(unit)
                    .font(.body.weight(.medium))
            }
            .foregroundStyle(.primary)
        }
        .frame(minWidth: 70, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue("\(value)\(spokenUnit)")
    }
}
