import SwiftUI
import ComposableArchitecture

struct HomeView: View {
    @Bindable var store: StoreOf<HomeFeature>
    let mapStore: StoreOf<IndoorMapFeature>
    @State private var recommendationPosition: Int? = 0

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    recommendationSection
                    popularBooksSection
                }
                .padding(.top, 22)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
        }
        .background(Color(uiColor: .systemBackground))
        .toolbar {
            LibraryTopBar(title: "추천", onBasket: { store.send(.basketButtonTapped) })
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { store.send(.task) }
        .task(id: LibraryInfoTaskID(bookIDs: store.popularBooks.map(\.id), sessionID: store.recommendationSessionID)) {
            await store.send(.loadLibraryInfo).finish()
        }
        .onDisappear { store.send(.libraryInfoCancelled) }
        .task(id: upcomingCoverURLs) {
            await BookCoverPipeline.shared.prefetch(upcomingCoverURLs)
        }
        .navigationDestination(
            item: $store.scope(state: \.detail, action: \.detail)
        ) { detailStore in
            BookDetailMapView(
                store: detailStore,
                mapStore: mapStore
            )
        }
        .navigationDestination(
            item: $store.scope(state: \.basket, action: \.basket)
        ) { basketStore in
            BookBasketView(store: basketStore)
                .toolbar(.visible, for: .navigationBar)
        }
        .navigationDestination(
            item: $store.scope(state: \.shelfMap, action: \.shelfMap)
        ) { shelfMapStore in
            BookShelfMapView(store: shelfMapStore)
                .toolbar(.visible, for: .navigationBar)
        }
    }

    private struct LibraryInfoTaskID: Equatable {
        let bookIDs: [Book.ID]
        let sessionID: UUID?
    }
    
    private var upcomingCoverURLs: [URL] {
        let nextIndex = max(0, (recommendationPosition ?? 0) + 1)
        return store.recommendedBooks.dropFirst(nextIndex).prefix(2).compactMap(\.imageURL)
    }
    
    private var recommendationSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .bottom) {
                Text("당신에게\n추천하는 책 \(store.recommendationCount)선.")
                    .font(.system(size: 18, weight: .medium))
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                
                Spacer()
                
                HStack(spacing: 0) {
                    recommendationButton(direction: -1)
                    recommendationButton(direction: 1)
                }
            }
            .padding(.horizontal, 16)
            
            if store.recommendedBooks.isEmpty {
                if store.isLoadingRecommendations || store.recommendationSessionID == nil {
                    VStack(spacing: 8) {
                        ProgressView("추천 도서를 준비하고 있어요")
                        Text("처음에는 잠시 걸릴 수 있어요.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 206)
                }
            } else {
                recommendationCarousel
            }

            if let message = store.recommendationErrorMessage {
                VStack(alignment: .leading, spacing: 10) {
                    Label(message, systemImage: "exclamationmark.circle")
                    if !store.recommendedBooks.isEmpty {
                        Text("이전 추천은 계속 볼 수 있어요.")
                            .font(.footnote)
                    }
                    Button("다시 시도") { store.send(.retryRecommendationsButtonTapped) }
                        .buttonStyle(.bordered)
                        .disabled(store.isPreparingRecommendations)
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
            }
        }
    }

    private var recommendationCarousel: some View {
        ZStack(alignment: .bottom) {
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .bottom, spacing: 12) {
                        ForEach(
                            Array(store.recommendedBooks.prefix(6).enumerated()),
                            id: \.element.id
                        ) { index, book in
                            
                            Button {
                                store.send(.bookSelected(book))
                            } label: {
                                HomeBookCover(book: book, width: 122, height: 180)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(book.title)
                            .id(index)
                        }
                    }
                    .scrollTargetLayout()
                }
                .contentMargins(.horizontal, 32, for: .scrollContent)
                .scrollIndicators(.hidden)
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $recommendationPosition, anchor: .leading)
                .padding(.bottom, 26)
            }
            .frame(height: 206)
            .onChange(of: store.recommendedBooks.map(\.id)) { _, _ in
                recommendationPosition = 0
            }
    }
    
    private var popularBooksSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button {
                store.send(.popularBooksButtonTapped)
            } label: {
                HStack(spacing: 12) {
                    Text("‘\(store.departmentName)’에서 많이 빌린")
                        .font(.system(size: 18, weight: .semibold))
                        .multilineTextAlignment(.leading)
                    
                    Spacer(minLength: 0)
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 16, weight: .medium))
                }
                .foregroundStyle(.primary)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(true) // TODO: AppFeature의 전체 보기 화면 연결 후 활성화
            .padding(.horizontal, 16)
            
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 12) {
                    if store.popularBooks.isEmpty {
                        ForEach(0..<4, id: \.self) { _ in
                            HomePopularBookCard(book: nil, libraryInfo: nil)
                                .accessibilityLabel("인기 도서 자리")
                        }
                    } else {
                        ForEach(store.popularBooks) { book in
                            Button {
                                store.send(.bookSelected(book))
                            } label: {
                                HomePopularBookCard(
                                    book: book,
                                    libraryInfo: store.libraryInfo[book.id]
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("책 소개 보기")
                        }
                    }
                }
            }
            .contentMargins(.horizontal, 16, for: .scrollContent)
            .scrollIndicators(.hidden)

            if store.libraryInfo.values.contains(.failed) {
                Button("소장 정보 다시 불러오기") { store.send(.loadLibraryInfo) }
                    .font(.footnote)
                    .buttonStyle(.bordered)
                    .padding(.horizontal, 16)
            }
        }
    }
    
    private func recommendationButton(direction: Int) -> some View {
        let position = recommendationPosition ?? 0
        let target = min(max(position + direction, 0), store.recommendationCount - 1)
        
        return Button {
            withAnimation(.easeInOut(duration: 0.25)) {
                recommendationPosition = target
            }
        } label: {
            Image(systemName: direction < 0 ? "chevron.left" : "chevron.right")
                .font(.system(size: 18, weight: .medium))
                .frame(width: 36, height: 44)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .disabled(target == position)
        .accessibilityLabel(direction < 0 ? "이전 추천 도서" : "다음 추천 도서")
    }
}

private struct HomeBookCover: View {
    let book: Book?
    let width: CGFloat
    let height: CGFloat
    
    var body: some View {
        // 홈 카드는 전체가 상세 이동 버튼이다. 재시도는 열린 상세 화면에서 제공한다.
        BookCoverView(url: book?.imageURL, isbn: book?.isbn, allowsRetry: false)
        .frame(width: width, height: height)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .accessibilityHidden(true)
    }
}

private struct HomePopularBookCard: View {
    let book: Book?
    let libraryInfo: HomeFeature.LibraryInfoState?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HomeBookCover(book: book, width: 96, height: 140)
                .padding(.bottom, 8)
            
            if let book {
                Text(BookText.plainText(book.title))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                
                Text(BookText.plainText(book.author))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                placeholder(width: 88, height: 14)
                placeholder(width: 76, height: 10)
            }
            
            libraryInformation
        }
        .frame(width: 96, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var libraryInformation: some View {
        switch libraryInfo {
        case .none, .loading:
            placeholder(width: 86, height: 10)
            placeholder(width: 48, height: 10)
        case .loaded(let info):
            VStack(alignment: .leading, spacing: 8) {
                Text(info.location ?? (info.holdings.isEmpty ? "소장 정보 없음" : "위치 정보 없음"))
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
                if info.additionalLocationCount > 0 {
                    Text("외 \(info.additionalLocationCount)곳 소장")
                        .foregroundStyle(.secondary)
                }
                switch info.availability {
                case .available:
                    Text("대출 가능").foregroundStyle(.green)
                case .unavailable:
                    Text("이용 불가").foregroundStyle(.red)
                case .unknown:
                    Text("대출 정보 없음").foregroundStyle(.secondary)
                }
            }
            .font(.system(size: 12))
        case .failed, .unavailable:
            VStack(alignment: .leading, spacing: 8) {
                Text("소장 정보 확인 불가")
                Text("대출 상태 확인 필요")
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
        }
    }
    
    private func placeholder(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(.primary.opacity(0.10))
            .frame(width: width, height: height)
            .accessibilityHidden(true)
    }
}

#Preview("추천 홈 · 다크") {
    NavigationStack {
        HomeView(
            store: Store(initialState: HomeFeature.State()) { HomeFeature() },
            mapStore: Store(initialState: IndoorMapFeature.State()) { IndoorMapFeature() }
        )
    }
    .preferredColorScheme(.dark)
}
