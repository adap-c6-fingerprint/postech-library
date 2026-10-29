import Foundation
import ComposableArchitecture

@Reducer
struct HomeFeature {
    @ObservableState
    struct State: Equatable {
        // MARK: - 추천 카드와 학과 목록
        var recommendedBooks: [Book] = []
        var popularBooks: [Book] = []
        var departmentName = ""
        var libraryInfo: [Book.ID: LibraryInfoState] = [:]
        var libraryInfoGeneration = 0

        // MARK: - 하위 화면
        @Presents var detail: BookDetailFeature.State?
        @Presents var basket: BookBasketFeature.State?
        @Presents var shelfMap: BookShelfMapFeature.State?

        var recommendationCount: Int {
            recommendedBooks.isEmpty ? 6 : min(recommendedBooks.count, 6)
        }

        // MARK: - 조회 상태와 다음 접속용 캐시
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

    enum Action {
        case task
        case recommendationSessionStarted
        case retryRecommendationsButtonTapped
        case recommendationsRestored(UUID, CachedRecommendations?)
        case recommendationsLoaded(UUID, CachedRecommendations)
        case popularBooksLoaded([Book])
        case loadLibraryInfo
        case libraryInfoLoaded(generation: Int, Book.ID, [BookHolding])
        case libraryInfoFailed(generation: Int, Book.ID)
        case libraryInfoCancelled
        case departmentChanged(String)

        case bookSelected(Book)
        case basketButtonTapped
        case profileButtonTapped
        case popularBooksButtonTapped
        case detail(PresentationAction<BookDetailFeature.Action>)
        case basket(PresentationAction<BookBasketFeature.Action>)
        case shelfMap(PresentationAction<BookShelfMapFeature.Action>)
        case delegate(Delegate)

        case recommendationsFailed(UUID, String)
        case popularBooksFailed(String)

        enum Delegate {
            case favoritesChanged(Set<[String?]>)
            case showProfile
            case showPopularBooks
        }
    }

    @Dependency(\.bookRecommendationClient)
    var bookRecommendationClient

    @Dependency(\.departmentPopularBooksClient)
    var departmentPopularBooksClient

    @Dependency(\.recommendationCacheClient) var recommendationCacheClient
    @Dependency(\.bookFavoritesClient) var bookFavoritesClient
    @Dependency(\.bookHoldingsClient) var bookHoldingsClient
    @Dependency(\.userProfileClient) var userProfileClient
    @Dependency(\.uuid) var uuid

    private nonisolated enum CancelID: Hashable, Sendable {
        case recommendationSession
        case libraryInfo
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .task:
                var effects: [Effect<Action>] = []

                if state.recommendedBooks.isEmpty && state.recommendationSessionID == nil {
                    effects.append(.send(.recommendationSessionStarted))
                }

                if state.popularBooks.isEmpty {
                    state.popularBooksErrorMessage = nil
                    effects.append(loadPopularBooks())
                }

                return .merge(effects)

            case .recommendationSessionStarted:
                let sessionID = uuid()
                state.recommendationSessionID = sessionID
                state.isLoadingRecommendations = true
                state.isPreparingRecommendations = true
                state.nextRecommendationsSavedAt = nil
                state.recommendationErrorMessage = nil
                let displayedCovers = state.recommendedBooks.compactMap(\.imageURL)
                    + [state.detail?.book.imageURL].compactMap { $0 }
                return loadRecommendations(sessionID: sessionID, retaining: displayedCovers)

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

            case .loadLibraryInfo:
                return loadLibraryInfo(state: &state)

            case let .libraryInfoLoaded(generation, bookID, holdings):
                guard state.libraryInfoGeneration == generation,
                      state.popularBooks.contains(where: { $0.id == bookID }) else { return .none }
                state.libraryInfo[bookID] = .loaded(BookCardLibraryInfo(holdings: holdings))
                return .none

            case let .libraryInfoFailed(generation, bookID):
                guard state.libraryInfoGeneration == generation,
                      state.popularBooks.contains(where: { $0.id == bookID }) else { return .none }
                // 조회 실패 후 예전 대출 상태를 현재 상태처럼 남겨 두지 않는다.
                state.libraryInfo[bookID] = .failed
                return .none

            case .libraryInfoCancelled:
                state.libraryInfoGeneration += 1
                return .cancel(id: CancelID.libraryInfo)

            case let .departmentChanged(name):
                state.departmentName = name
                return .none

            case let .bookSelected(book):
                state.detail = BookDetailFeature.State(
                    book: book, isFavorite: bookFavoritesClient.load().contains(book.recordKey)
                )
                return .none

            case .basketButtonTapped:
                state.basket = BookBasketFeature.State()
                return .none

            case let .basket(.presented(.delegate(.startGuidance(books)))):
                state.shelfMap = BookShelfMapFeature.State(books: books)
                return .none

            case let .detail(.presented(.delegate(.startGuidance(book)))):
                state.shelfMap = BookShelfMapFeature.State(book: book)
                return .none

            case .profileButtonTapped:
                return .send(.delegate(.showProfile))

            case .popularBooksButtonTapped:
                return .send(.delegate(.showPopularBooks))

            case let .detail(.presented(.delegate(.favoritesChanged(keys)))):
                return .send(.delegate(.favoritesChanged(keys)))

            case .detail, .basket, .shelfMap, .delegate:
                return .none
            }
        }
        .ifLet(\.$detail, action: \.detail) {
            BookDetailFeature()
        }
        .ifLet(\.$basket, action: \.basket) {
            BookBasketFeature()
        }
        .ifLet(\.$shelfMap, action: \.shelfMap) {
            BookShelfMapFeature()
        }
    }

    private func loadLibraryInfo(state: inout State) -> Effect<Action> {
        state.libraryInfoGeneration += 1
        let generation = state.libraryInfoGeneration
        let visibleIDs = Set(state.popularBooks.map(\.id))
        state.libraryInfo = state.libraryInfo.filter { visibleIDs.contains($0.key) }
        var requests: [(bookID: Book.ID, recordID: String)] = []
        for book in state.popularBooks {
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

    private func loadRecommendations(sessionID: UUID, retaining covers: [URL]) -> Effect<Action> {
        .run { [bookRecommendationClient, recommendationCacheClient] send in
            do {
                await recommendationCacheClient.retainDisplayedCovers(covers)
                // 저장본이 손상되어도 캐시가 없는 경우와 같은 최초 조회 경로로 복구한다.
                let cached = try? await recommendationCacheClient.restore()
                try Task.checkCancellation()
                await send(.recommendationsRestored(sessionID, cached))
                let books = try await bookRecommendationClient.fetch(6)
                try Task.checkCancellation()
                guard !books.isEmpty else {
                    await send(.recommendationsFailed(sessionID, "추천 도서를 찾지 못했어요. 다시 시도해 주세요."))
                    return
                }
                let prepared = try await recommendationCacheClient.prepare(books)
                try Task.checkCancellation()
                await send(.recommendationsLoaded(sessionID, prepared))
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                await send(.recommendationsFailed(sessionID, "추천 도서를 준비하지 못했어요. 다시 시도해 주세요."))
            }
        }
        .cancellable(id: CancelID.recommendationSession, cancelInFlight: true)
    }

    private func loadPopularBooks() -> Effect<Action> {
        .run { [userProfileClient, departmentPopularBooksClient] send in
            do {
                // 저장된 프로필의 학과로 제목을 채우고 같은 학과의 인기 도서를 조회한다.
                let departmentName = try await userProfileClient.load().departmentName
                await send(.departmentChanged(departmentName))
                let books = try await departmentPopularBooksClient.fetch(departmentName, 6)
                try Task.checkCancellation()
                await send(.popularBooksLoaded(books))
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                await send(.popularBooksFailed(error.localizedDescription))
            }
        }
    }
}
