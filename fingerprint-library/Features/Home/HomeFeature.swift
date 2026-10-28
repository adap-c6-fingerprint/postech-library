import Foundation
import ComposableArchitecture

@Reducer
struct HomeFeature {
    @ObservableState
    struct State: Equatable {
        var recommendedBooks: [Book] = []
        var popularBooks: [Book] = []
        var departmentName = ""
        var libraryInfo: [Book.ID: LibraryInfo] = [:]

        @Presents var detail: BookDetailFeature.State?
        @Presents var basket: BookBasketFeature.State?

        var recommendationCount: Int {
            recommendedBooks.isEmpty ? 6 : min(recommendedBooks.count, 6)
        }

        var recommendationErrorMessage: String? = nil
        var popularBooksErrorMessage: String? = nil
        var recommendationSessionID: UUID?
        var isLoadingRecommendations = false
        var isPreparingRecommendations = false
        var nextRecommendationsSavedAt: Date?
    }

    // 도서관 소장 정보는 기존 Book 모델과 분리한다.
    struct LibraryInfo: Equatable, Sendable {
        var location: String?
        var isAvailable: Bool?
    }

    enum Action {
        case task
        case recommendationSessionStarted
        case retryRecommendationsButtonTapped
        case recommendationsRestored(UUID, CachedRecommendations?)
        case recommendationsLoaded(UUID, CachedRecommendations)
        case popularBooksLoaded([Book])
        case libraryInfoLoaded([Book.ID: LibraryInfo])
        case departmentChanged(String)

        case bookSelected(Book)
        case basketButtonTapped
        case profileButtonTapped
        case popularBooksButtonTapped
        case detail(PresentationAction<BookDetailFeature.Action>)
        case basket(PresentationAction<BookBasketFeature.Action>)
        case delegate(Delegate)

        case recommendationsFailed(UUID, String)
        case popularBooksFailed(String)

        enum Delegate {
            case showProfile
            case showPopularBooks
        }
    }

    @Dependency(\.bookRecommendationClient)
    var bookRecommendationClient

    @Dependency(\.departmentPopularBooksClient)
    var departmentPopularBooksClient

    @Dependency(\.recommendationCacheClient) var recommendationCacheClient
    @Dependency(\.uuid) var uuid

    private nonisolated enum CancelID: Hashable, Sendable {
        case recommendationSession
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
                    effects.append(loadPopularBooks(departmentName: state.departmentName))
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

            case let .libraryInfoLoaded(info):
                state.libraryInfo = info
                return .none

            case let .departmentChanged(name):
                state.departmentName = name
                return .none

            case let .bookSelected(book):
                state.detail = BookDetailFeature.State(book: book)
                return .none

            case .basketButtonTapped:
                state.basket = BookBasketFeature.State()
                return .none

            case .basket(.presented(.delegate(.startGuidance))):
                // TODO: 경로 요약 페이지(07)를 구현하면 선택한 책을 넘겨 화면을 연다.
                return .none

            case .profileButtonTapped:
                return .send(.delegate(.showProfile))

            case .popularBooksButtonTapped:
                return .send(.delegate(.showPopularBooks))

            case .detail, .basket, .delegate:
                return .none
            }
        }
        .ifLet(\.$detail, action: \.detail) {
            BookDetailFeature()
        }
        .ifLet(\.$basket, action: \.basket) {
            BookBasketFeature()
        }
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

    private func loadPopularBooks(departmentName: String) -> Effect<Action> {
        .run { [departmentPopularBooksClient] send in
            do {
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
