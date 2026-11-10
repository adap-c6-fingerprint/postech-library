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
        var hasSyncedProfile = false
        // displayedProfile을 한 번이라도 기록했는지. 온보딩을 건너뛰면 기록한 프로필도 nil이라 nil만으로는 '아직 안 불러옴'과 구분되지 않는다.
        var isProfileComplete: Bool {
            guard let userProfile else { return false }
            return RecommendationDataset.AffiliationPath(key: userProfile.affiliationKey) != nil
                && !userProfile.interests.isEmpty
        }
        // 소속과 관심 분야를 모두 설정했는지. 아니면 학과 추천 섹션을 '맞춤 정보를 설정해 주세요' 안내로 가린다. (이슈 #396)
        var departmentName: String { userProfile?.departmentName ?? "" }
        // "'수학과'에서 많이 빌린" 제목에 쓰는 소속 이름. 따로 복사해 두지 않고 프로필에서 바로 읽는다.
        var isRecommendationExpanded = true
        var showsKulumiCovers = false
        var isFirstVisitAfterOnboarding = false
        // ✅ 온보딩을 마치고 처음 홈을 여는 경우 true. 학과별 추천을 하드데이터 랜덤 6권으로만 보여준다. (Q4)
        var libraryInfo: [Book.ID: LibraryInfoState] = [:]
        var libraryInfoGeneration = 0
        var libraryInfoPending: [Book.ID] = []
        var libraryInfoInFlight: Set<Book.ID> = []
        var libraryInfoUpdatedAt: [Book.ID: Date] = [:]

        @Presents var detail: BookDetailFeature.State?
        @Presents var cart: BookCartFeature.State?
        @Presents var favorites: BookFavoritesFeature.State?
        @Presents var shelfMap: BookShelfMapFeature.State?
        @Presents var myPage: MyPageFeature.State?

        var recommendationCount: Int {
            let count = DatasetRecommendation.displayCount
            return recommendedBooks.isEmpty ? count : min(recommendedBooks.count, count)
        }

        var booksForLibraryInfo: [Book] {
            guard case let .loaded(books) = departmentRecommendations else { return popularBooks }
            let previewIDs = Set(popularBooks.map(\.id))
            return popularBooks + books.filter { !previewIDs.contains($0.id) }
        }

        var recommendationErrorMessage: String? = nil
        var recommendationCoverFiles: [Book.ID: URL] = [:]
        var popularBooksErrorMessage: String? = nil
        var recommendationSessionID: UUID?
        var isLoadingRecommendations = false
        var isPreparingRecommendations = false
        var recommendationLoadMode: RecommendationLoadMode = .restore
        var carouselPreparation: CarouselPreparation = .idle
        var isRefreshingRecommendations: Bool {
            isPreparingRecommendations && recommendationLoadMode == .carouselRefresh
        }
        var nextRecommendationsSavedAt: Date?
    }

    enum RecommendationLoadMode {
        case restore
        case profileChanged
        case carouselRefresh
    }

    enum CarouselPreparation: Equatable {
        case idle
        case loading(UUID)
        case finished(Result<[Book], CarouselFailure>)
    }

    enum CarouselFailure: Error, Equatable {
        case insufficientBooks
        case preparationFailed

        var message: String {
            switch self {
            case .insufficientBooks: "새 추천 6권을 찾지 못했어요."
            case .preparationFailed: "새 추천을 불러오지 못했어요."
            }
        }
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
        case recommendationNearEnd
        case recommendationEndReached
        case carouselPreparationFinished(UUID, Result<[Book], CarouselFailure>)
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
        case cartButtonTapped
        case favoritesButtonTapped
        case profileButtonTapped
        case detail(PresentationAction<BookDetailFeature.Action>)
        case cart(PresentationAction<BookCartFeature.Action>)
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
    @Dependency(\.analyticsClient) private var analytics
    @Dependency(\.date.now) var now

    private nonisolated enum CancelID: Hashable, Sendable {
        case recommendationSession
        case carouselPreparation
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
                return startRecommendationSession(state: &state, mode: .restore)

            case .recommendationNearEnd:
                guard !state.showsKulumiCovers, !state.recommendedBooks.isEmpty,
                      state.carouselPreparation == .idle else { return .none }
                return prepareCarouselReplacement(state: &state)

            case .recommendationEndReached:
                guard !state.showsKulumiCovers, !state.recommendedBooks.isEmpty,
                      !state.isRefreshingRecommendations else { return .none }
                let sessionID = beginRecommendationSession(state: &state, mode: .carouselRefresh)
                if case let .finished(result) = state.carouselPreparation {
                    return applyCarouselReplacement(
                        result, sessionID: sessionID, retaining: displayedRecommendationCovers(state)
                    )
                }
                let prepare = state.carouselPreparation == .idle ? prepareCarouselReplacement(state: &state) : .none
                return .merge(.cancel(id: CancelID.recommendationSession), prepare)

            case let .carouselPreparationFinished(id, result):
                guard state.carouselPreparation == .loading(id) else { return .none }
                state.carouselPreparation = .finished(result)
                guard state.isRefreshingRecommendations, let sessionID = state.recommendationSessionID else { return .none }
                return applyCarouselReplacement(
                    result, sessionID: sessionID, retaining: displayedRecommendationCovers(state)
                )

            case .retryRecommendationsButtonTapped:
                guard !state.isPreparingRecommendations else { return .none }
                let mode = state.recommendationLoadMode
                return .send(mode == .carouselRefresh ? .recommendationEndReached : .recommendationSessionStarted)

            case let .recommendationsRestored(sessionID, cached):
                guard state.recommendationSessionID == sessionID else { return .none }
                if let cached {
                    let booksChanged = state.recommendedBooks.map(\.id) != cached.books.map(\.id)
                    analytics.record(.init(.recommendationLoadCompleted, [
                        .kind: .text("restored"), .bookCount: .integer(cached.books.count)
                    ]))
                    state.recommendedBooks = cached.books
                    state.recommendationCoverFiles = cached.coverFiles
                    state.isLoadingRecommendations = false
                    if booksChanged {
                        state.carouselPreparation = .idle
                        return .cancel(id: CancelID.carouselPreparation)
                    }
                }
                return .none

            case let .recommendationsLoaded(sessionID, prepared):
                guard state.recommendationSessionID == sessionID else { return .none }
                let isCarouselRefresh = state.recommendationLoadMode == .carouselRefresh
                analytics.record(.init(.recommendationLoadCompleted, [
                    .kind: .text(isCarouselRefresh ? "carousel_refresh" : "prepared_for_next_visit"),
                    .bookCount: .integer(prepared.books.count)
                ]))
                state.isLoadingRecommendations = false
                state.isPreparingRecommendations = false
                state.nextRecommendationsSavedAt = prepared.savedAt
                // 접속 시 미리 준비한 추천은 다음 접속에 쓰고, 스크롤로 요청한 추천은 바로 교체한다.
                if isCarouselRefresh || state.recommendedBooks.isEmpty {
                    state.recommendedBooks = prepared.books
                    state.recommendationCoverFiles = prepared.coverFiles
                }
                if isCarouselRefresh { state.carouselPreparation = .idle }
                state.recommendationErrorMessage = nil
                return .none

            case let .recommendationsFailed(sessionID, message):
                guard state.recommendationSessionID == sessionID else { return .none }
                analytics.record(.init(.recommendationFailed, [.errorCode: .text("preparation_failed")]))
                state.isLoadingRecommendations = false
                state.isPreparingRecommendations = false
                if state.recommendationLoadMode == .carouselRefresh { state.carouselPreparation = .idle }
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
                      state.libraryInfoInFlight.remove(bookID) != nil else { return .none }
                if let book = state.booksForLibraryInfo.first(where: { $0.id == bookID }) {
                    state.libraryInfo[bookID] = .loaded(BookCardLibraryInfo(holdings: holdings))
                    state.libraryInfoUpdatedAt[bookID] = now
                    bookLocationCacheClient.record(book, holdings)
                }
                return startNextLibraryInfoRequests(state: &state)

            case let .libraryInfoFailed(generation, bookID):
                guard state.libraryInfoGeneration == generation,
                      state.libraryInfoInFlight.remove(bookID) != nil else { return .none }
                if state.booksForLibraryInfo.contains(where: { $0.id == bookID }) {
                    state.libraryInfo[bookID] = .failed
                    state.libraryInfoUpdatedAt[bookID] = nil
                }
                // 서비스가 제한된 자동 재시도를 마친 실패다. 나머지 책의 조회는 계속한다.
                return startNextLibraryInfoRequests(state: &state)

            case .libraryInfoCancelled:
                return cancelLibraryInfo(state: &state)

            case let .upcomingCoversChanged(urls):
                return .run { [bookCoverClient] _ in
                    await bookCoverClient.prefetch(urls)
                    // 표지 미리 받기를 Effect로 시킴
                }
                

            case let .bookSelected(book):
                analytics.record(.init(.recommendationSelected, [.bookRecordID: .text(AnalyticsEvent.bookID(book))]))
                state.detail = BookDetailFeature.State(
                    book: book, cachedCoverURL: state.recommendationCoverFiles[book.id],
                    isFavorite: bookFavoritesClient.load().contains(book.recordKey)
                )
                return .none

            case .cartButtonTapped:
                state.cart = BookCartFeature.State()
                return .none

            case .favoritesButtonTapped:
                state.favorites = BookFavoritesFeature.State()
                return .none

            case let .favorites(.presented(.delegate(.favoritesChanged(keys)))):
                return .send(.delegate(.favoritesChanged(keys)))

            case let .cart(.presented(.delegate(.startGuidance(books)))):
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

            case .detail, .cart, .favorites, .shelfMap, .myPage, .delegate:
                return .none
            }
        }
        .ifLet(\.$detail, action: \.detail) {
            BookDetailFeature()
        }
        .ifLet(\.$cart, action: \.cart) {
            BookCartFeature()
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
        let books = state.booksForLibraryInfo
        let visibleIDs = Set(books.map(\.id))
        state.libraryInfo = state.libraryInfo.filter { visibleIDs.contains($0.key) }
        state.libraryInfoUpdatedAt = state.libraryInfoUpdatedAt.filter { visibleIDs.contains($0.key) }
        state.libraryInfoPending.removeAll { !visibleIDs.contains($0) }

        for book in books {
            guard !state.libraryInfoInFlight.contains(book.id) else { continue }
            if case .loaded = state.libraryInfo[book.id],
               let updatedAt = state.libraryInfoUpdatedAt[book.id],
               now.timeIntervalSince(updatedAt) < 60 {
                continue
            }
            guard BookHoldingsClient.recordID(for: book) != nil else {
                state.libraryInfo[book.id] = .unavailable
                continue
            }
            state.libraryInfo[book.id] = .loading
            if !state.libraryInfoPending.contains(book.id) {
                state.libraryInfoPending.append(book.id)
            }
        }
        // 목록이 추가돼도 진행 중 요청의 세대와 성공 결과는 유지한다.
        if state.libraryInfoInFlight.isEmpty && !state.libraryInfoPending.isEmpty {
            state.libraryInfoGeneration += 1
        }
        return startNextLibraryInfoRequests(state: &state)
    }

    private func startNextLibraryInfoRequests(state: inout State) -> Effect<Action> {
        var effects: [Effect<Action>] = []
        while state.libraryInfoInFlight.count < 3 && !state.libraryInfoPending.isEmpty {
            let bookID = state.libraryInfoPending.removeFirst()
            guard let book = state.booksForLibraryInfo.first(where: { $0.id == bookID }),
                  let recordID = BookHoldingsClient.recordID(for: book) else { continue }
            state.libraryInfoInFlight.insert(bookID)
            let generation = state.libraryInfoGeneration
            effects.append(.run { [bookHoldingsClient] send in
                do {
                    let holdings = try await bookHoldingsClient.fetch(recordID)
                    try Task.checkCancellation()
                    await send(.libraryInfoLoaded(generation: generation, bookID, holdings))
                } catch {
                    guard !Task.isCancelled else { return }
                    await send(.libraryInfoFailed(generation: generation, bookID))
                }
            }.cancellable(id: CancelID.libraryInfo))
        }
        // 한 권이 완료될 때마다 다음 요청을 넣어 느린 한 권이 뒤쪽 목록을 막지 않게 한다.
        return .merge(effects)
    }

    private func cancelLibraryInfo(state: inout State) -> Effect<Action> {
        state.libraryInfoGeneration += 1
        state.libraryInfoPending = []
        state.libraryInfoInFlight = []
        return .cancel(id: CancelID.libraryInfo)
    }

    private func syncWithProfile(state: inout State) -> (cancel: Effect<Action>, reload: Effect<Action>) {
    // 화면의 목록을 만들 때 쓴 프로필(displayedProfile)과 지금 프로필(userProfile)을 비교한다.
    // 소속이 바뀌면 학과 추천을, 관심 분야가 바뀌면 '당신을 위한 추천'을 비우고 새 프로필로 다시 불러온다.
    // cancel: 예전 프로필로 진행 중인 조회 취소. reload: 새 프로필로 바로 다시 받을 조회.
        let current = state.userProfile
        guard state.hasSyncedProfile else {
            state.hasSyncedProfile = true
            state.displayedProfile = current
            // 처음 불러오는 경우. 목록이 아직 비어 있으므로 비울 것이 없다.
            return (.none, .none)
        }
        let previous = state.displayedProfile
        // 온보딩을 건너뛴 상태였다면 nil이다.
        guard let current, current != previous else { return (.none, .none) }
        state.displayedProfile = current
        var cancels: [Effect<Action>] = []
        var reload: Effect<Action> = .none

        if current.affiliationKey != previous?.affiliationKey {
            state.popularBooks = []
            state.popularBooksErrorMessage = nil
            state.departmentRecommendations = .loading
            if !state.libraryInfoInFlight.isEmpty || !state.libraryInfoPending.isEmpty {
                cancels.append(cancelLibraryInfo(state: &state))
            }
            state.libraryInfo = [:]
            state.libraryInfoUpdatedAt = [:]
            cancels.append(.cancel(id: CancelID.popularBooks))
            cancels.append(.cancel(id: CancelID.departmentRecommendations))
            // 예전 소속으로 받던 조회가 늦게 도착해 새 목록을 덮지 않게 취소한다.
            // 빈 목록은 각 화면의 조회(.task, departmentRecommendationsRequested)가 새 소속으로 다시 채운다.
        }

        if current.interests != previous?.interests {
        // 건너뛴 뒤 마이페이지에서 프로필을 처음 만든 경우(nil → 프로필)도 여기로 와서, 하드데이터 전체로 고른 추천을 새 관심 분야로 다시 받는다.
            state.recommendedBooks = []
            state.recommendationCoverFiles = [:]
            reload = startRecommendationSession(state: &state, mode: .profileChanged)
            // 저장해 둔 추천은 예전 관심 분야로 만든 것이라 꺼내지 않고 새로 받는다.
            // 진행 중이던 예전 세션은 같은 취소 ID(cancelInFlight)로 자동 취소된다.
        }
        return (.merge(cancels), reload)
    }

    private func startRecommendationSession(state: inout State, mode: RecommendationLoadMode) -> Effect<Action> {
        state.carouselPreparation = .idle
        let sessionID = beginRecommendationSession(state: &state, mode: mode)
        return .merge(
            .cancel(id: CancelID.carouselPreparation),
            loadRecommendations(sessionID: sessionID, retaining: displayedRecommendationCovers(state), restoresCache: mode == .restore)
        )
    }

    private func beginRecommendationSession(state: inout State, mode: RecommendationLoadMode) -> UUID {
        let sessionID = uuid()
        state.recommendationSessionID = sessionID
        state.recommendationLoadMode = mode
        state.isLoadingRecommendations = mode != .carouselRefresh
        state.isPreparingRecommendations = true
        state.nextRecommendationsSavedAt = nil
        state.recommendationErrorMessage = nil
        return sessionID
    }

    private func displayedRecommendationCovers(_ state: State) -> [URL] {
        Array(state.recommendationCoverFiles.values)
            + [state.detail?.cachedCoverURL].compactMap { $0 }
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
                let prepared = try await homeRecommendationForYouClient.refresh(
                    DatasetRecommendation.displayCount, covers
                )
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

    private func prepareCarouselReplacement(state: inout State) -> Effect<Action> {
        let id = uuid()
        let displayedBooks = state.recommendedBooks
        state.carouselPreparation = .loading(id)
        return .run { [homeRecommendationForYouClient, bookCoverClient] send in
            do {
                let books = try await homeRecommendationForYouClient.prepareReplacement(
                    DatasetRecommendation.displayCount, displayedBooks
                )
                try Task.checkCancellation()
                await send(.carouselPreparationFinished(id, .success(books)))
                await bookCoverClient.prefetch(books.prefix(2).compactMap(\.imageURL))
            } catch is CancellationError {
                return
            } catch HomeRecommendationForYouError.insufficientReplacements {
                await send(.carouselPreparationFinished(id, .failure(.insufficientBooks)))
            } catch {
                guard !Task.isCancelled else { return }
                await send(.carouselPreparationFinished(id, .failure(.preparationFailed)))
            }
        }
        .cancellable(id: CancelID.carouselPreparation, cancelInFlight: true)
    }

    private func applyCarouselReplacement(
        _ result: Result<[Book], CarouselFailure>, sessionID: UUID, retaining covers: [URL]
    ) -> Effect<Action> {
        .run { [homeRecommendationForYouClient] send in
            do {
                let prepared = try await homeRecommendationForYouClient.saveReplacement(result.get(), covers)
                try Task.checkCancellation()
                await send(.recommendationsLoaded(sessionID, prepared))
            } catch is CancellationError {
                return
            } catch let failure as CarouselFailure {
                await send(.recommendationsFailed(sessionID, failure.message))
            } catch {
                guard !Task.isCancelled else { return }
                await send(.recommendationsFailed(sessionID, CarouselFailure.preparationFailed.message))
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
