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

        var recommendationCount: Int {
            recommendedBooks.isEmpty ? 6 : min(recommendedBooks.count, 6)
        }

        var recommendationErrorMessage: String? = nil
        var popularBooksErrorMessage: String? = nil
    }

    // 도서관 소장 정보는 기존 Book 모델과 분리한다.
    struct LibraryInfo: Equatable, Sendable {
        var location: String?
        var isAvailable: Bool?
    }

    enum Action {
        case task
        case recommendationsLoaded([Book])
        case popularBooksLoaded([Book])
        case libraryInfoLoaded([Book.ID: LibraryInfo])
        case departmentChanged(String)

        case bookSelected(Book)
        case basketButtonTapped
        case profileButtonTapped
        case popularBooksButtonTapped
        case detail(PresentationAction<BookDetailFeature.Action>)
        case delegate(Delegate)

        case recommendationsFailed(String)
        case popularBooksFailed(String)

        enum Delegate {
            case showBasket
            case showProfile
            case showPopularBooks
        }
    }

    @Dependency(\.bookRecommendationClient)
    var bookRecommendationClient

    @Dependency(\.departmentPopularBooksClient)
    var departmentPopularBooksClient

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .task:
                var effects: [Effect<Action>] = []

                if state.recommendedBooks.isEmpty {
                    state.recommendationErrorMessage = nil
                    effects.append(loadRecommendations())
                }

                if state.popularBooks.isEmpty {
                    state.popularBooksErrorMessage = nil
                    effects.append(loadPopularBooks(departmentName: state.departmentName))
                }

                return .merge(effects)

            case let .recommendationsLoaded(books):
                state.recommendedBooks = books
                state.recommendationErrorMessage = books.isEmpty
                    ? "추천 도서를 찾지 못했어요."
                    : nil
                return .none

            case let .recommendationsFailed(message):
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
                return .send(.delegate(.showBasket))

            case .profileButtonTapped:
                return .send(.delegate(.showProfile))

            case .popularBooksButtonTapped:
                return .send(.delegate(.showPopularBooks))

            case .detail, .delegate:
                return .none
            }
        }
        .ifLet(\.$detail, action: \.detail) {
            BookDetailFeature()
        }
    }

    private func loadRecommendations() -> Effect<Action> {
        .run { [bookRecommendationClient] send in
            do {
                let books = try await bookRecommendationClient.fetch(6)
                try Task.checkCancellation()
                await send(.recommendationsLoaded(books))
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                await send(.recommendationsFailed(error.localizedDescription))
            }
        }
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
