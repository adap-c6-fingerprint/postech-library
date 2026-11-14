import ComposableArchitecture
import Foundation

@Reducer
struct BookShelfMapFeature {
    @ObservableState
    struct State: Equatable {
        let books: [Book]
        var sourceFavoriteMarkerID: String?
        var map = IndoorMapFeature.State()
        var holdings: [Book.ID: BookHoldingsState] = [:]
        var holdingRequestIDs: [Book.ID: Int] = [:]
        var resolutions: [Book.ID: [ShelfResolution]] = [:]
        var details: IdentifiedArrayOf<BookDetailFeature.State>

        init(book: Book) {
            books = [book]
            details = [BookDetailFeature.State(book: book)]
        }

        init?(books: [Book]) {
            guard BookRouteSelection.allows(bookCount: books.count) else { return nil }
            self.init(previewing: books)
        }

        init?(previewing books: [Book]) {
            guard !books.isEmpty, Set(books.map(\.id)).count == books.count else { return nil }
            self.books = books
            details = IdentifiedArray(uniqueElements: books.map { BookDetailFeature.State(book: $0) })
        }

        func shelves(for bookID: Book.ID) -> [IndoorShelfLabel] {
            (resolutions[bookID] ?? []).preferredRouteShelves
        }

        var shelves: [IndoorShelfLabel] {
            var seen = Set<String>()
            return books.flatMap { shelves(for: $0.id) }.filter { seen.insert($0.id).inserted }
        }
    }

    enum Action {
        case task
        case prepareMap
        case loadMissingHoldings
        case retryHoldingsTapped(Book.ID)
        case holdingsLoaded(Book.ID, requestID: Int, [BookHolding])
        case holdingsFailed(Book.ID, requestID: Int, String)
        case resolveLocations
        case bookShelfTapped(Book.ID)
        case candidateTapped(Book.ID, fixtureNumber: String)
        case map(IndoorMapFeature.Action)
        case details(IdentifiedActionOf<BookDetailFeature>)
        case guidanceRequested(Book)
        case delegate(Delegate)

        @CasePathable
        enum Delegate: Equatable {
            case startGuidance([Book])
        }
    }

    @Dependency(\.bookHoldingsClient) var holdingsClient
    @Dependency(\.bookLocationCacheClient) var bookLocationCacheClient
    private nonisolated struct CancelID: Hashable, Sendable {
        let instance: UUID
        let bookID: Book.ID
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .task:
                return .merge(.send(.prepareMap), .send(.loadMissingHoldings))

            case .prepareMap:
                return .send(.map(.retryTapped))

            case .loadMissingHoldings:
                var effects: [Effect<Action>] = []
                for book in state.books where state.holdings[book.id] == nil {
                    effects.append(loadHoldings(book.id, state: &state))
                }
                return .merge(effects)

            case .retryHoldingsTapped(let bookID):
                return loadHoldings(bookID, state: &state)

            case .holdingsLoaded(let bookID, let requestID, let holdings):
                guard state.holdings[bookID] == .loading,
                      state.holdingRequestIDs[bookID] == requestID else { return .none }
                state.holdings[bookID] = .loaded(holdings)
                if let book = state.books.first(where: { $0.id == bookID }) {
                    bookLocationCacheClient.record(book, holdings)
                }
                return .send(.resolveLocations)

            case .holdingsFailed(let bookID, let requestID, let message):
                guard state.holdings[bookID] == .loading,
                      state.holdingRequestIDs[bookID] == requestID else { return .none }
                state.holdings[bookID] = .failed(message)
                return .none

            case .resolveLocations:
                state.resolutions = [:]
                if let map = state.map.map {
                    for book in state.books {
                        if case .loaded(let holdings) = state.holdings[book.id] {
                            state.resolutions[book.id] = ShelfResolver().resolve(
                                holdings, on: map, labels: state.map.shelfLabels
                            )
                        }
                    }
                }
                focus(state.shelves, state: &state)
                return .none

            case .bookShelfTapped(let bookID):
                focus(state.shelves(for: bookID), state: &state)
                return .none

            case .candidateTapped(let bookID, let fixtureNumber):
                guard let shelf = state.shelves(for: bookID).first(where: { $0.fixtureNumber == fixtureNumber }) else {
                    return .none
                }
                state.map.selectedFloorID = shelf.floorID
                state.map.requestCamera(.features([shelf.mapElementID]))
                return .none

            case .map(.mapLoaded):
                return .send(.resolveLocations)

            case .map(.shelfLabelsLoaded(let requestID, _)):
                guard state.map.isLoadingShelfLabels, requestID == state.map.shelfLabelRequestID else { return .none }
                return .send(.resolveLocations)

            case .map(.retryTapped):
                guard state.map.map != nil, state.map.loadError == nil else {
                    state.resolutions = [:]
                    return .none
                }
                if state.map.shelfLabels.isEmpty, !state.map.isLoadingShelfLabels {
                    return .send(.map(.retryShelfLabelsTapped))
                }
                return .send(.resolveLocations)

            case .map(.retryShelfLabelsTapped):
                state.resolutions = [:]
                return .none

            case let .guidanceRequested(book):
                return .send(.delegate(.startGuidance([book])))

            case .delegate:
                return .none

            case .map, .details:
                return .none
            }
        }
        .forEach(\.details, action: \.details) { BookDetailFeature() }
        Scope(state: \.map, action: \.map) { IndoorMapFeature() }
    }

    private func loadHoldings(_ bookID: Book.ID, state: inout State) -> Effect<Action> {
        guard let book = state.books.first(where: { $0.id == bookID }), state.holdings[bookID] != .loading else {
            return .none
        }
        guard let recordID = BookHoldingsClient.recordID(for: book) else {
            state.holdings[bookID] = .failed(BookHoldingsError.invalidRecordID.localizedDescription)
            return .none
        }
        state.resolutions[bookID] = nil
        state.holdings[bookID] = .loading
        let requestID = (state.holdingRequestIDs[bookID] ?? 0) + 1
        state.holdingRequestIDs[bookID] = requestID
        return .run { [holdingsClient] send in
            do {
                let holdings = try await holdingsClient.fetch(recordID)
                try Task.checkCancellation()
                await send(.holdingsLoaded(bookID, requestID: requestID, holdings))
            } catch {
                guard !Task.isCancelled else { return }
                await send(.holdingsFailed(bookID, requestID: requestID, error.localizedDescription))
            }
        }.cancellable(id: CancelID(instance: state.map.instanceID, bookID: bookID), cancelInFlight: true)
    }

    private func focus(_ shelves: [IndoorShelfLabel], state: inout State) {
        guard let floorID = shelves.first(where: { $0.floorID == state.map.selectedFloorID })?.floorID
                ?? shelves.first?.floorID else { return }
        state.map.selectedFloorID = floorID
        state.map.requestCamera(.features(shelves.filter { $0.floorID == floorID }.map(\.mapElementID)))
    }
}
