import ComposableArchitecture

@Reducer
struct HomeFeature {
    @ObservableState
    struct State: Equatable {
        var recommendedBooks: [Book] = []
        var popularBooks: [Book] = []
        var departmentName = "반도체공학과"
        var libraryInfo: [Book.ID: LibraryInfo] = [:]

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

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .task:
                // TODO: 홈 도서 API Client를 연결하고 조회 결과 액션을 보낸다.
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
}
