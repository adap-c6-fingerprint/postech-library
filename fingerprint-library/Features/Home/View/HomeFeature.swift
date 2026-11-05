import Foundation
import ComposableArchitecture

@Reducer
struct HomeFeature {
    @ObservableState
    struct State: Equatable {
        var recommendedBooks: [Book] = []
        var popularBooks: [Book] = []
        var departmentRecommendations: DepartmentRecommendationsState = .loading
        @Shared(.userProfile) var userProfile: UserProfile?
        // 앱 전체가 함께 쓰는 프로필. 온보딩·마이페이지에서 바꾼 값이 그대로 보인다.
        var displayedProfile: UserProfile?
        // 지금 화면의 추천 목록들을 만들 때 쓴 프로필. userProfile과 다르면 목록을 새 프로필로 다시 불러온다.
        var departmentName: String { userProfile?.departmentName ?? "" }
        // "'수학과'에서 많이 빌린" 제목에 쓰는 소속 이름. 따로 복사해 두지 않고 프로필에서 바로 읽는다.
        var isRecommendationExpanded = true
        var showsKulumiCovers = false
        var isFirstVisitAfterOnboarding = false
        // ✅ 온보딩을 마치고 처음 홈을 여는 경우 true. 학과별 추천을 하드데이터 랜덤 6권으로만 보여준다. (Q4)
        var libraryInfo: [Book.ID: LibraryInfoState] = [:]
        var libraryInfoGeneration = 0

        @Presents var detail: BookDetailFeature.State?
        @Presents var basket: BookBasketFeature.State?
        @Presents var favorites: BookFavoritesFeature.State?
        @Presents var shelfMap: BookShelfMapFeature.State?
        @Presents var myPage: MyPageFeature.State?

        var recommendationCount: Int {
            recommendedBooks.isEmpty ? 6 : min(recommendedBooks.count, 6)
        }

        var booksForLibraryInfo: [Book] {
            guard case let .loaded(books) = departmentRecommendations else { return popularBooks }
            let previewIDs = Set(popularBooks.map(\.id))
            return popularBooks + books.filter { !previewIDs.contains($0.id) }
        }

        var recommendationErrorMessage: String? = nil
        var popularBooksErrorMessage: String? = nil
        var recommendationSessionID: UUID?
        var isLoadingRecommendations = false
        var isPreparingRecommendations = false
        var nextRecommendationsSavedAt: Date?
    }

    enum LibraryInfoState: Equatable {
        case loading
        case loaded(BookCardLibraryInfo)
        case unavailable
        case failed
    }

    enum DepartmentRecommendationsState: Equatable {
        case loading
        case loaded([Book])
        case failed(String)
    }

    enum Action {
        case task
        case recommendationSessionStarted // 당신을 위한 추천 불러오기 시작
        case retryRecommendationsButtonTapped // 추천 불러오기 실패시 재시도
        case recommendationsRestored(UUID, CachedRecommendations?)
        case recommendationsLoaded(UUID, CachedRecommendations)
        case popularBooksLoaded([Book])
        case departmentRecommendationsRequested
        case departmentRecommendationsLoaded([Book])
        case departmentRecommendationsFailed(String)
        case loadLibraryInfo
        case libraryInfoLoaded(generation: Int, Book.ID, [BookHolding])
        case libraryInfoFailed(generation: Int, Book.ID)
        case libraryInfoCancelled
        case upcomingCoversChanged( [URL] ) // 다음에 볼 표지 주소 목록이 바뀜

        case bookSelected(Book)
        case basketButtonTapped
        case favoritesButtonTapped
        case profileButtonTapped
        case detail(PresentationAction<BookDetailFeature.Action>)
        case basket(PresentationAction<BookBasketFeature.Action>)
        case favorites(PresentationAction<BookFavoritesFeature.Action>)
        case shelfMap(PresentationAction<BookShelfMapFeature.Action>)
        case myPage(PresentationAction<MyPageFeature.Action>)
        case delegate(Delegate)

        case recommendationsFailed(UUID, String)
        case popularBooksFailed(String)

        enum Delegate {
            case favoritesChanged(Set<[String?]>)
            case showProfile
        }
    }

    @Dependency(\.homeRecommendationForYouClient) var homeRecommendationForYouClient
    // 홈화면 상단 - 당신을 위한 추천 리스트
    @Dependency(\.bookCoverClient) var bookCoverClient // 표지 URL 호출
    @Dependency(\.departmentPopularBooksClient)
    var departmentPopularBooksClient // 학과별 인기 도서

    @Dependency(\.bookFavoritesClient) var bookFavoritesClient
    @Dependency(\.bookHoldingsClient) var bookHoldingsClient // 대출가능여부
    @Dependency(\.bookLocationCacheClient) var bookLocationCacheClient
    @Dependency(\.uuid) var uuid

    private nonisolated enum CancelID: Hashable, Sendable {
        case recommendationSession
        case departmentRecommendations
        case libraryInfo
        case popularBooks
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .task:
                let sync = syncWithProfile(state: &state)
                // 프로필이 바뀌었으면 먼저 예전 목록을 비운다. 아래에서 빈 목록을 새 프로필로 다시 불러온다.
                var effects = [sync.reload]

                if state.recommendedBooks.isEmpty && state.recommendationSessionID == nil {
                    effects.append(.send(.recommendationSessionStarted))
                }

                if state.popularBooks.isEmpty {
                    state.popularBooksErrorMessage = nil
                    effects.append(loadPopularBooks(
                        affiliationKey: state.userProfile?.affiliationKey ?? [],
                        isInitial: state.isFirstVisitAfterOnboarding
                    ))
                    // ✅ 최초 표시 여부를 함께 넘긴다.
                }

                return .concatenate(sync.cancel, .merge(effects))
                // 예전 조회를 취소한 뒤에 새 조회를 시작한다.

            case .recommendationSessionStarted:
                return startRecommendationSession(state: &state, restoresCache: true)

            case .retryRecommendationsButtonTapped:
                guard !state.isPreparingRecommendations else { return .none }
                return .send(.recommendationSessionStarted)

            case let .recommendationsRestored(sessionID, cached):
                guard state.recommendationSessionID == sessionID else { return .none }
                if let cached {
                    state.recommendedBooks = cached.displayBooks
                    state.isLoadingRecommendations = false
                }
                return .none

            case let .recommendationsLoaded(sessionID, prepared):
                guard state.recommendationSessionID == sessionID else { return .none }
                state.isLoadingRecommendations = false
                state.isPreparingRecommendations = false
                state.nextRecommendationsSavedAt = prepared.savedAt
                // 이번 접속의 목록 A는 유지한다. 완성된 B는 다음 접속에서 복원한다.
                if state.recommendedBooks.isEmpty {
                    state.recommendedBooks = prepared.displayBooks
                }
                state.recommendationErrorMessage = nil
                return .none

            case let .recommendationsFailed(sessionID, message):
                guard state.recommendationSessionID == sessionID else { return .none }
                state.isLoadingRecommendations = false
                state.isPreparingRecommendations = false
                state.recommendationErrorMessage = message
                return .none

            case let .popularBooksLoaded(books):
                state.popularBooks = books
                state.popularBooksErrorMessage = books.isEmpty
                    ? "인기 도서를 찾지 못했어요."
                    : nil
                return .none

            case let .popularBooksFailed(message):
                state.popularBooksErrorMessage = message
                return .none

            case .departmentRecommendationsRequested:
                let sync = syncWithProfile(state: &state)
                if case .loaded = state.departmentRecommendations {
                    return .concatenate(sync.cancel, sync.reload)
                }
                state.departmentRecommendations = .loading
                let affiliationKey = state.userProfile?.affiliationKey ?? []
                let load: Effect<Action> = .run { [departmentPopularBooksClient] send in
                    do {
                        let books = try await departmentPopularBooksClient.fetchAll(affiliationKey)
                        try Task.checkCancellation()
                        await send(.departmentRecommendationsLoaded(books))
                    } catch {
                        guard !Task.isCancelled else { return }
                        await send(.departmentRecommendationsFailed(error.localizedDescription))
                    }
                }
                .cancellable(id: CancelID.departmentRecommendations, cancelInFlight: true)
                return .concatenate(sync.cancel, .merge(sync.reload, load))

            case let .departmentRecommendationsLoaded(books):
                state.departmentRecommendations = .loaded(books)
                return .none

            case let .departmentRecommendationsFailed(message):
                state.departmentRecommendations = .failed(message)
                return .none

            case .loadLibraryInfo:
                return loadLibraryInfo(state: &state)

            case let .libraryInfoLoaded(generation, bookID, holdings):
                guard state.libraryInfoGeneration == generation,
                      let book = state.booksForLibraryInfo.first(where: { $0.id == bookID }) else { return .none }
                state.libraryInfo[bookID] = .loaded(BookCardLibraryInfo(holdings: holdings))
                bookLocationCacheClient.record(book, holdings)
                return .none

            case let .libraryInfoFailed(generation, bookID):
                guard state.libraryInfoGeneration == generation,
                      state.booksForLibraryInfo.contains(where: { $0.id == bookID }) else { return .none }
                // 조회 실패 후 예전 대출 상태를 현재 상태처럼 남겨 두지 않는다.
                state.libraryInfo[bookID] = .failed
                return .none

            case .libraryInfoCancelled:
                state.libraryInfoGeneration += 1
                return .cancel(id: CancelID.libraryInfo)

            case let .upcomingCoversChanged(urls):
                return .run { [bookCoverClient] _ in
                    await bookCoverClient.prefetch(urls)
                    // 표지 미리 받기를 Effect로 시킴
                }
                

            case let .bookSelected(book):
                state.detail = BookDetailFeature.State(
                    book: book, isFavorite: bookFavoritesClient.load().contains(book.recordKey)
                )
                return .none

            case .basketButtonTapped:
                state.basket = BookBasketFeature.State()
                return .none

            case .favoritesButtonTapped:
                state.favorites = BookFavoritesFeature.State()
                return .none

            case let .favorites(.presented(.delegate(.favoritesChanged(keys)))):
                return .send(.delegate(.favoritesChanged(keys)))

            case let .basket(.presented(.delegate(.startGuidance(books)))):
                state.shelfMap = BookShelfMapFeature.State(books: books)
                return .none

            case let .detail(.presented(.delegate(.startGuidance(book)))):
                state.shelfMap = BookShelfMapFeature.State(book: book)
                return .none

            case .profileButtonTapped:
                state.myPage = MyPageFeature.State()
                // 찜 목록처럼 지금 탭의 내비게이션 안에서 마이페이지를 연다.
                return .none

            case let .detail(.presented(.delegate(.favoritesChanged(keys)))):
                return .send(.delegate(.favoritesChanged(keys)))

            case .detail, .basket, .favorites, .shelfMap, .myPage, .delegate:
                return .none
            }
        }
        .ifLet(\.$detail, action: \.detail) {
            BookDetailFeature()
        }
        .ifLet(\.$basket, action: \.basket) {
            BookBasketFeature()
        }
        .ifLet(\.$favorites, action: \.favorites) {
            BookFavoritesFeature()
        }
        .ifLet(\.$shelfMap, action: \.shelfMap) {
            BookShelfMapFeature()
        }
        .ifLet(\.$myPage, action: \.myPage) {
            MyPageFeature()
        }
    }

    private func loadLibraryInfo(state: inout State) -> Effect<Action> {
        state.libraryInfoGeneration += 1
        let generation = state.libraryInfoGeneration
        let books = state.booksForLibraryInfo
        let visibleIDs = Set(books.map(\.id))
        state.libraryInfo = state.libraryInfo.filter { visibleIDs.contains($0.key) }
        var requests: [(bookID: Book.ID, recordID: String)] = []
        for book in books {
            guard let recordID = BookHoldingsClient.recordID(for: book) else {
                state.libraryInfo[book.id] = .unavailable
                continue
            }
            state.libraryInfo[book.id] = .loading
            requests.append((book.id, recordID))
        }
        return .run { [bookHoldingsClient, requests] send in
            // 표지와 서지정보 표시는 막지 않고 최대 3건씩 조회한다.
            for start in stride(from: 0, to: requests.count, by: 3) {
                guard !Task.isCancelled else { return }
                await withTaskGroup(of: Void.self) { group in
                    for request in requests[start..<min(start + 3, requests.count)] {
                        group.addTask {
                            do {
                                let holdings = try await bookHoldingsClient.fetch(request.recordID)
                                try Task.checkCancellation()
                                await send(.libraryInfoLoaded(generation: generation, request.bookID, holdings))
                            } catch {
                                guard !Task.isCancelled else { return }
                                await send(.libraryInfoFailed(generation: generation, request.bookID))
                            }
                        }
                    }
                }
            }
        }
        .cancellable(id: CancelID.libraryInfo, cancelInFlight: true)
    }

    private func syncWithProfile(state: inout State) -> (cancel: Effect<Action>, reload: Effect<Action>) {
    // 화면의 목록을 만들 때 쓴 프로필(displayedProfile)과 지금 프로필(userProfile)을 비교한다.
    // 소속이 바뀌면 학과 추천을, 관심 분야가 바뀌면 '당신을 위한 추천'을 비우고 새 프로필로 다시 불러온다.
    // cancel: 예전 프로필로 진행 중인 조회 취소. reload: 새 프로필로 바로 다시 받을 조회.
        let current = state.userProfile
        guard let previous = state.displayedProfile else {
            state.displayedProfile = current
            // 처음 불러오는 경우. 목록이 아직 비어 있으므로 비울 것이 없다.
            return (.none, .none)
        }
        guard let current, current != previous else { return (.none, .none) }
        state.displayedProfile = current
        var cancels: [Effect<Action>] = []
        var reload: Effect<Action> = .none

        if current.affiliationKey != previous.affiliationKey {
            state.popularBooks = []
            state.popularBooksErrorMessage = nil
            state.departmentRecommendations = .loading
            cancels.append(.cancel(id: CancelID.popularBooks))
            cancels.append(.cancel(id: CancelID.departmentRecommendations))
            // 예전 소속으로 받던 조회가 늦게 도착해 새 목록을 덮지 않게 취소한다.
            // 빈 목록은 각 화면의 조회(.task, departmentRecommendationsRequested)가 새 소속으로 다시 채운다.
        }

        if current.interests != previous.interests {
            state.recommendedBooks = []
            reload = startRecommendationSession(state: &state, restoresCache: false)
            // 저장해 둔 추천은 예전 관심 분야로 만든 것이라 꺼내지 않고 새로 받는다.
            // 진행 중이던 예전 세션은 같은 취소 ID(cancelInFlight)로 자동 취소된다.
        }
        return (.merge(cancels), reload)
    }

    private func startRecommendationSession(state: inout State, restoresCache: Bool) -> Effect<Action> {
        let sessionID = uuid()
        state.recommendationSessionID = sessionID
        state.isLoadingRecommendations = true
        state.isPreparingRecommendations = true
        state.nextRecommendationsSavedAt = nil
        state.recommendationErrorMessage = nil
        let displayedCovers = state.recommendedBooks.compactMap(\.imageURL)
            + [state.detail?.book.imageURL].compactMap { $0 }
        return loadRecommendations(sessionID: sessionID, retaining: displayedCovers, restoresCache: restoresCache)
    }

    private func loadRecommendations(sessionID: UUID, retaining covers: [URL], restoresCache: Bool) -> Effect<Action> {
        .run { [homeRecommendationForYouClient] send in
            do {
                if restoresCache {
                    let cached = await homeRecommendationForYouClient.restore(covers)
                    // ①② 보이는 표지 지키기 + 꺼내기.
                    try Task.checkCancellation()
                    await send(.recommendationsRestored(sessionID, cached))
                    // ③ 그대로.
                }
                let prepared = try await homeRecommendationForYouClient.refresh(6)
                // ④⑤⑥ 새로 받기 + 0권 검사 + 저장.
                try Task.checkCancellation()
                await send(.recommendationsLoaded(sessionID, prepared))
            } catch is CancellationError {
                return
            } catch HomeRecommendationForYouError.empty {
                await send(.recommendationsFailed(sessionID, "추천 도서를 찾지 못했어요. 다시 시도해 주세요."))
                // 추천 도서 0권일 때
            } catch {
                guard !Task.isCancelled else { return }
                await send(.recommendationsFailed(sessionID, "추천 도서를 준비하지 못했어요. 다시 시도해 주세요."))
            }
        }
        .cancellable(id: CancelID.recommendationSession, cancelInFlight: true)
    }

    private func loadPopularBooks(affiliationKey: [String], isInitial: Bool) -> Effect<Action> {
        .run { [departmentPopularBooksClient] send in
            do {
                // 프로필의 소속 경로로 같은 소속의 추천 도서를 고른다. 제목은 State.departmentName이 프로필에서 바로 읽는다.
                let books = try await departmentPopularBooksClient.fetch(affiliationKey, 6, isInitial)
                // ✅ 학과 이름 대신 소속 경로로 조회한다. 같은 이름의 학부·대학원 학과가 각자의 목록을 받는다.
                try Task.checkCancellation()
                await send(.popularBooksLoaded(books))
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                await send(.popularBooksFailed(error.localizedDescription))
            }
        }
        .cancellable(id: CancelID.popularBooks, cancelInFlight: true)
    }
}
