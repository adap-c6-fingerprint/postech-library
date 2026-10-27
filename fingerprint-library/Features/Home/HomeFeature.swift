import ComposableArchitecture
import Foundation

@Reducer
struct HomeFeature {
    @ObservableState
    struct State: Equatable {
        var recommendedBooks: [Book] = []
        var popularBooks: [Book] = []
        var departmentName = ""
        var libraryInfo: [Book.ID: LibraryInfo] = [:]
        var coldStartBooks: [RecommendedBook] = []
        // 찜·검색 기록이 없을 때 보여 줄 첫 추천 결과 (최대 6권).
        var personalizedBooks: [RecommendedBook] = []
        // 찜·검색 기록이 있을 때 보여 줄 맞춤 추천 결과 (최대 6권).

        @Presents var detail: BookDetailFeature.State?

        var recommendationCount: Int {
            recommendedBooks.isEmpty ? 6 : min(recommendedBooks.count, 6)
        }
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
        case coldStartLoaded([RecommendedBook])
        case coldStartFailed(String)
        case personalizedLoaded([RecommendedBook])
        case personalizedFailed(String)

        case bookSelected(Book)
        case basketButtonTapped
        case profileButtonTapped
        case popularBooksButtonTapped
        case detail(PresentationAction<BookDetailFeature.Action>)
        case delegate(Delegate)

        enum Delegate {
            case showBasket
            case showProfile
            case showPopularBooks
        }
    }

    @Dependency(\.bookFavoritesClient) var bookFavoritesClient
    @Dependency(\.searchHistoryClient) var searchHistoryClient
    // 검색 화면과 같은 저장소(UserDefaults)를 읽어 기록이 있는지 확인한다.
    @Dependency(\.coldStartRecommendationClient) var coldStartClient
    @Dependency(\.personalizedRecommendationClient) var personalizedClient

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .task:
                // TODO: 홈 도서 API Client를 연결하고 조회 결과 액션을 보낸다.
                let favoriteKeys = bookFavoritesClient.load()
                let recentQueries = searchHistoryClient.load()
                let interests = ColdStartRecommendation.placeholderInterests
                // TODO: 온보딩 완성 후 저장된 UserProfile.interests로 교체한다.
                guard PersonalizedRecommendation.shouldApply(
                    favoriteKeys: favoriteKeys,
                    recentQueries: recentQueries
                ) else { return coldStartEffect(interests: interests) }
                // 찜·검색 기록이 둘 다 없으면 첫 추천을 쓴다.
                let input = PersonalizedRecommendationInput(
                    favoriteKeys: favoriteKeys,
                    recentQueries: recentQueries,
                    interests: interests
                )
                return .run { [personalizedClient] send in
                    await send(.personalizedLoaded(try await personalizedClient.fetch(input)))
                } catch: { error, send in
                    await send(.personalizedFailed(error.localizedDescription))
                }

            case let .personalizedLoaded(books):
                state.personalizedBooks = books
                return .none

            case .personalizedFailed:
                state.personalizedBooks = []
                return coldStartEffect(interests: ColdStartRecommendation.placeholderInterests)
                // 맞춤 추천이 실패하면(네트워크·키워드 없음 등) 홈이 비지 않게 첫 추천으로 대신한다.

            case let .coldStartLoaded(books):
                state.coldStartBooks = books
                return .none

            case .coldStartFailed:
                state.coldStartBooks = []
                return .none

            case let .recommendationsLoaded(books):
                state.recommendedBooks = books
                return .none

            case let .popularBooksLoaded(books):
                state.popularBooks = books
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

    private func coldStartEffect(interests: [String]) -> Effect<Action> {
    // 첫 추천을 불러오는 작업. 기록이 없을 때와 맞춤 추천이 실패했을 때 함께 쓴다.
        .run { [coldStartClient] send in
            await send(.coldStartLoaded(try await coldStartClient.fetch(interests)))
        } catch: { error, send in
            await send(.coldStartFailed(error.localizedDescription))
        }
    }
}
