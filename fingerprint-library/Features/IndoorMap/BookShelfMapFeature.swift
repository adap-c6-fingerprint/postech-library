import ComposableArchitecture
import Foundation

/// #53의 임시 서가 표시. 책마다 서가 하나를 목업으로 연결한다.
@Reducer
struct BookShelfMapFeature {
    @ObservableState
    struct State: Equatable {
        let books: [Book]
        var map = IndoorMapFeature.State()

        init(book: Book) {
            books = [book]
        }

        init?(books: [Book]) {
            guard BookRouteSelection.allows(bookCount: books.count) else { return nil }
            self.books = books
        }

        /// 실제 위치 대신 사용할 서가 세 곳. 같은 책은 진입 경로·선택 순서와 무관하게 같은 목업에 연결한다.
        private static let mockFixtureNumbers = ["S-3F-616-B", "S-3F-612-B", "S-3F-608-B"]

        func shelf(for bookID: Book.ID) -> IndoorShelfLabel? {
            guard books.contains(where: { $0.id == bookID }) else { return nil }
            let index = bookID.utf8.reduce(1) { ($0 + Int($1)) % Self.mockFixtureNumbers.count }
            let fixtureNumber = Self.mockFixtureNumbers[index]
            return map.shelfLabels.first { $0.fixtureNumber == fixtureNumber }
        }

        var shelves: [IndoorShelfLabel] {
            books.compactMap { shelf(for: $0.id) }
        }

        var highlightedFeatureIDs: Set<IndoorMapElement.ID> {
            Set(shelves.map(\.mapElementID))
        }
    }

    enum Action: Equatable {
        case task
        case focusShelfTapped
        case bookShelfTapped(Book.ID)
        case map(IndoorMapFeature.Action)
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .task:
                // 임시 서가 표시에는 현재 위치 수신이나 경로 탐색을 시작하지 않는다.
                return .send(.map(.retryTapped))

            case .bookShelfTapped(let bookID):
                guard let shelf = state.shelf(for: bookID) else { return .none }
                state.map.selectedFloorID = shelf.floorID
                state.map.requestCamera(.features([shelf.mapElementID]))
                return .none

            case .focusShelfTapped:
                focusShelf(&state)
                return .none

            case .map(.mapLoaded):
                return .send(.focusShelfTapped)

            case .map(.shelfLabelsLoaded(let requestID, _)):
                guard state.map.isLoadingShelfLabels, requestID == state.map.shelfLabelRequestID else { return .none }
                return .send(.focusShelfTapped)

            case .map:
                return .none
            }
        }
        Scope(state: \.map, action: \.map) { IndoorMapFeature() }
    }

    private func focusShelf(_ state: inout State) {
        guard let floor = state.map.map?.floors.first(where: { $0.ordinal == 2 })
        else { return }
        state.map.selectedFloorID = floor.id
        let ids = state.shelves.map(\.mapElementID)
        state.map.requestCamera(ids.isEmpty ? .initialFloor(floor.id) : .features(ids))
    }
}
