import SwiftUI
import ComposableArchitecture

struct HomeView: View {
    @Bindable var store: StoreOf<HomeFeature>
    let mapStore: StoreOf<IndoorMapFeature>
    @State private var recommendationPosition: Int? = 0
    @State private var homeScrollPosition = ScrollPosition(edge: .top)
    @State private var isHomeAtTop = true

    private static let kulumiCoverNames = (1...6).map { "KulumiCover\($0)" }

    private enum Destination: Hashable {
        case departmentRecommendations
    }

    private var recommendationLayout: RecommendationLayout {
        store.isRecommendationExpanded ? .expanded : .standard
    }

    private enum RecommendationLayout {
        case standard
        case expanded

        var coverWidth: CGFloat { self == .expanded ? 208 : 141.06 }
        var coverHeight: CGFloat { self == .expanded ? 306 : 206.42 }
        var coverCornerRadius: CGFloat { self == .expanded ? 14 : 10 }
        var spacing: CGFloat { self == .expanded ? 22 : 16 }
        var horizontalInset: CGFloat { self == .expanded ? 66 : 48 }
        var bottomInset: CGFloat { self == .expanded ? 22 : 14 }
        var shelfHeight: CGFloat { self == .expanded ? 156 : 110 }
        var shelfWidth: CGFloat? { self == .standard ? 707 : nil }
        var carouselHeight: CGFloat { coverHeight + bottomInset }
    }

    var body: some View {
        NavigationStack {
            homeContent
        }
        .task(id: store.userProfile) { store.send(.task) }
        // 프로필(소속·관심 분야)이 바뀌면 다시 실행해 바뀐 목록을 새로 불러온다. 마이페이지에서 돌아올 때 바로 반영된다.
        // 추천 홈에서 목록으로 이동해도 두 화면이 공유하는 소장 정보 조회를 이어간다.
        .task(id: LibraryInfoTaskID(bookIDs: store.booksForLibraryInfo.map(\.id), sessionID: store.recommendationSessionID)) {
            // Effect의 수명은 reducer가 관리한다. 목록 ID 변경으로 기존 요청을 취소하지 않는다.
            store.send(.loadLibraryInfo)
        }
        .onDisappear { store.send(.libraryInfoCancelled) }
    }

    private var homeContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                recommendationSection
                popularBooksSection
            }
            .padding(.bottom, 24)
        }
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top <= 1
        } action: { _, isAtTop in
            isHomeAtTop = isAtTop
        }
        .scrollIndicators(.hidden)
        .scrollPosition($homeScrollPosition)
        .onChange(of: store.showsKulumiCovers) { _, isActive in
            guard isActive else { return }
            homeScrollPosition.scrollTo(edge: .top)
            recommendationPosition = 0
        }
        .safeAreaBar(edge: .top, spacing: 0) {
            LibraryTabTopBar(
                title: "추천",
                onFavorites: { store.send(.favoritesButtonTapped) },
                onCart: { store.send(.cartButtonTapped) },
                onProfile: { store.send(.profileButtonTapped) }
            )
            // 버튼 아래 여백까지 블러가 적용되는 상단바 영역에 포함한다.
            .padding(.bottom, LibraryTabIntroText.topBarSpacing)
        }
        .scrollEdgeEffectStyle(.hard, for: .top)
        .scrollEdgeEffectHidden(isHomeAtTop, for: .top)
        .background(Color(uiColor: .systemBackground))
        .toolbar(.hidden, for: .navigationBar)
        .task(id: upcomingCoverURLs) {
            await store.send(.upcomingCoversChanged(upcomingCoverURLs)).finish()
        }
        .navigationDestination(for: Destination.self) { _ in
            DepartmentRecommendationsView(store: store)
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
            item: $store.scope(state: \.cart, action: \.cart)
        ) { cartStore in
            BookCartView(store: cartStore)
                .toolbar(.visible, for: .navigationBar)
        }
        .navigationDestination(
            item: $store.scope(state: \.favorites, action: \.favorites)
        ) { favoritesStore in
            BookFavoritesView(store: favoritesStore)
        }
        .navigationDestination(
            item: $store.scope(state: \.shelfMap, action: \.shelfMap)
        ) { shelfMapStore in
            BookShelfMapView(store: shelfMapStore)
                .toolbar(.visible, for: .navigationBar)
        }
        .navigationDestination(
            item: $store.scope(state: \.myPage, action: \.myPage)
        ) { myPageStore in
            MyPageView(store: myPageStore, mapStore: mapStore)
        }
    }

    private struct LibraryInfoTaskID: Equatable {
        let bookIDs: [Book.ID]
        let sessionID: UUID?
    }
    
    private var upcomingCoverURLs: [URL] {
        guard !store.showsKulumiCovers else { return [] }
        let nextIndex = max(0, (recommendationPosition ?? 0) + 1)
        return store.recommendedBooks.dropFirst(nextIndex).prefix(2).compactMap {
            store.recommendationCoverFiles[$0.id] ?? $0.imageURL
        }
    }
    
    private var recommendationSection: some View {
        let recipient = store.showsKulumiCovers ? "쿠루미에게" : "당신에게"
        let count = store.showsKulumiCovers ? Self.kulumiCoverNames.count : store.recommendationCount

        return VStack(alignment: .leading, spacing: 20) {
            LibraryTabIntroText(title: "\(recipient)\n추천하는 책 \(count)선.")
            
            if store.showsKulumiCovers || !store.recommendedBooks.isEmpty {
                recommendationCarousel
            } else if store.isLoadingRecommendations || store.recommendationSessionID == nil {
                VStack(spacing: 8) {
                    ProgressView("추천 도서를 준비하고 있어요")
                    Text("처음에는 잠시 걸릴 수 있어요.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: recommendationLayout.carouselHeight)
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
        let books = store.recommendedBooks

        return ScrollView(.horizontal) {
            LazyHStack(alignment: .bottom, spacing: recommendationLayout.spacing) {
                if store.showsKulumiCovers {
                    ForEach(Self.kulumiCoverNames.indices, id: \.self) { index in
                        let book = books.indices.contains(index) ? books[index] : nil
                        recommendationCard(book, photoName: Self.kulumiCoverNames[index])
                            .id(index)
                    }
                } else {
                    ForEach(Array(books.prefix(6).enumerated()), id: \.element.id) { index, book in
                        recommendationCard(book)
                            .id(index)
                    }
                }
            }
            .scrollTargetLayout()
        }
        .contentMargins(.horizontal, recommendationLayout.horizontalInset, for: .scrollContent)
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $recommendationPosition, anchor: .leading)
        .padding(.bottom, recommendationLayout.bottomInset)
        .frame(height: recommendationLayout.carouselHeight)
        .overlay(alignment: .bottomLeading) {
            RecommendationShelfView(
                height: recommendationLayout.shelfHeight,
                width: recommendationLayout.shelfWidth,
                fillOpacity: 0.3
            )
            .padding(.leading, RecommendationShelfView.leadingInset)
        }
        .coordinateSpace(.named(RecommendationShelfView.carouselSpace))
        .onChange(of: store.recommendedBooks.map(\.id)) { _, _ in
            guard !store.showsKulumiCovers else { return }
            recommendationPosition = 0
        }
    }

    @ViewBuilder
    private func recommendationCard(_ book: Book?, photoName: String? = nil) -> some View {
        let cover = HomeBookCover(
            book: book,
            cachedURL: book.flatMap { store.recommendationCoverFiles[$0.id] },
            width: recommendationLayout.coverWidth,
            height: recommendationLayout.coverHeight,
            cornerRadius: recommendationLayout.coverCornerRadius,
            shelfHeight: recommendationLayout.shelfHeight,
            shelfWidth: recommendationLayout.shelfWidth,
            photoName: photoName
        )

        if let book {
            Button {
                store.send(.bookSelected(book))
            } label: {
                cover.accessibilityHidden(true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(book.title)
        } else {
            cover.accessibilityLabel("쿠루미 사진")
        }
    }
    
    private var popularBooksSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            if store.isProfileComplete {
                NavigationLink(value: Destination.departmentRecommendations) {
                    popularBooksHeader(store.departmentName.isEmpty ? "많이 빌린 도서" : "'\(store.departmentName)'에서 많이 빌린")
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)

                popularBooksRow
            } else {
                Button { store.send(.profileButtonTapped) } label: {
                    popularBooksHeader("맞춤 정보를 설정해 주세요.")
                }
                // 쉐브론(제목 줄)을 누르면 마이페이지로 이동한다.
                .buttonStyle(.plain)
                .padding(.horizontal, 16)

                popularBooksRow
                    .blur(radius: 5)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .overlay { Color.backgroundDefault.opacity(0.5) }
                    .overlay(alignment: .top) { profileSetupPrompt.padding(.top, 56) }
                // 피그마 '2.추천_온보딩 미완료시'(4100:27254): 책 목록을 흐리게 가리고 그 위에 설정 안내를 띄운다.
            }
        }
    }

    private func popularBooksHeader(_ title: String) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .typography(.title2)
                .multilineTextAlignment(.leading)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 16, weight: .medium))
                .padding(.trailing, 8)
                .accessibilityHidden(true)
        }
        .foregroundStyle(.textPrimary)
        .frame(minHeight: 28)
        .contentShape(Rectangle())
    }

    private var profileSetupPrompt: some View {
        VStack(spacing: 0) {
            Text("소속과 관심사 정보를 알려주시면\n나에게 어울리는 책을 추천해 드려요.")
                .typography(.caption1.weight(.bold))

            Button { store.send(.profileButtonTapped) } label: {
                Text("설정하러 가기 >")
                    .typography(.caption1)
                    .underline()
            }
            .buttonStyle(.plain)
        }
        .multilineTextAlignment(.center)
        .foregroundStyle(.textSecondary)
        .padding(.horizontal, 16)
    }
    // 블러 위 안내 문구와 '설정하러 가기' 버튼. 버튼도 마이페이지로 이동한다.

    private var popularBooksRow: some View {
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
    }
}

private struct HomeBookCover: View {
    let book: Book?
    var cachedURL: URL? = nil
    let width: CGFloat
    let height: CGFloat
    var cornerRadius: CGFloat = 4
    var shelfHeight: CGFloat? = nil
    var shelfWidth: CGFloat? = nil
    var photoName: String? = nil
    
    var body: some View {
        let style = CoverStyle(cornerRadius: cornerRadius, shelfHeight: shelfHeight, shelfWidth: shelfWidth)

        Group {
            if let photoName {
                let photo = Image(photoName).resizable()
                photo
                    .scaledToFit()
                    .frame(width: width, height: height, alignment: .top)
                    .background {
                        photo.scaledToFill()
                            .frame(width: width, height: height)
                            .blur(radius: 16)
                            .accessibilityHidden(true)
                    }
                    .modifier(style)
            } else {
                // 홈 카드는 전체가 상세 이동 버튼이다. 재시도는 열린 상세 화면에서 제공한다.
                BookCoverView(
                    url: book?.imageURL,
                    isbn: book?.isbn,
                    cachedURL: cachedURL,
                    allowsRetry: false,
                    coverModifier: style
                )
            }
        }
        .frame(width: width, height: height)
    }

    private struct CoverStyle: ViewModifier {
        let cornerRadius: CGFloat
        let shelfHeight: CGFloat?
        let shelfWidth: CGFloat?

        func body(content: Content) -> some View {
            let cover = content
                .background(Color.primary.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            if let shelfHeight {
                cover.modifier(RecommendationShelfView.CoverBlur(height: shelfHeight, width: shelfWidth))
            } else {
                cover
            }
        }
    }
}

private struct HomePopularBookCard: View {
    let book: Book?
    let libraryInfo: HomeFeature.LibraryInfoState?

    private let coverWidth: CGFloat = 97

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HomeBookCover(book: book, width: coverWidth, height: 141.94)
                .accessibilityHidden(true)
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
        .frame(width: coverWidth, alignment: .leading)
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
    HomeView(
        store: Store(initialState: HomeFeature.State()) { HomeFeature() },
        mapStore: Store(initialState: IndoorMapFeature.State()) { IndoorMapFeature() }
    )
    .preferredColorScheme(.dark)
}
