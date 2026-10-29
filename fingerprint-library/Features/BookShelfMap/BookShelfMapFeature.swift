import ComposableArchitecture
import Foundation

/// 도서관 소장 정보 → 청구기호 범위 → 실제 IMDF fixture를 연결한다.
@Reducer
struct BookShelfMapFeature {
    enum HoldingsState: Equatable {
        case loading
        case loaded([BookHolding])
        case failed(String)
    }

    @ObservableState
    struct State: Equatable {
        let books: [Book]
        var map = IndoorMapFeature.State()
        var holdings: [Book.ID: HoldingsState] = [:]
        var holdingRequestIDs: [Book.ID: Int] = [:]
        var resolutions: [Book.ID: [BookHoldingShelfResolution]] = [:]

        init(book: Book) { books = [book] }

        init?(books: [Book]) {
            guard BookRouteSelection.allows(bookCount: books.count),
                  Set(books.map(\.id)).count == books.count else { return nil }
            self.books = books
        }

        func shelves(for bookID: Book.ID) -> [IndoorShelfLabel] {
            var seen = Set<String>()
            return (resolutions[bookID] ?? []).flatMap(\.shelves).filter { seen.insert($0.id).inserted }
        }

        var shelves: [IndoorShelfLabel] {
            var seen = Set<String>()
            return books.flatMap { shelves(for: $0.id) }.filter { seen.insert($0.id).inserted }
        }

        var highlightedFeatureIDs: Set<IndoorMapElement.ID> { Set(shelves.map(\.mapElementID)) }
    }

    enum Action: Equatable {
        case task
        case disappeared
        case retryHoldingsTapped(Book.ID)
        case holdingsLoaded(Book.ID, requestID: Int, [BookHolding])
        case holdingsFailed(Book.ID, requestID: Int, String)
        case resolveLocations
        case focusShelfTapped
        case bookShelfTapped(Book.ID)
        case candidateTapped(Book.ID, fixtureNumber: String)
        case map(IndoorMapFeature.Action)
    }

    @Dependency(\.bookHoldingsClient) var holdingsClient
    private nonisolated enum CancelID: Hashable, Sendable { case holdings(Book.ID) }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .task:
                var effects: [Effect<Action>] = [.send(.map(.retryTapped))]
                for book in state.books where state.holdings[book.id] == nil {
                    effects.append(loadHoldings(book.id, state: &state))
                }
                return .merge(effects)

            case .disappeared:
                // 테스트모드에서 다시 시작한 조회도 화면 수명에 맞춰 종료한다.
                return .merge([.send(.map(.disappeared))] + state.books.map {
                    .cancel(id: CancelID.holdings($0.id))
                })

            case .retryHoldingsTapped(let bookID):
                return loadHoldings(bookID, state: &state)

            case .holdingsLoaded(let bookID, let requestID, let holdings):
                guard state.holdings[bookID] == .loading,
                      state.holdingRequestIDs[bookID] == requestID else { return .none }
                state.holdings[bookID] = .loaded(holdings)
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
                            state.resolutions[book.id] = BookHoldingShelfResolver().resolve(
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

            case .focusShelfTapped:
                focus(state.shelves, state: &state)
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

            case .map:
                return .none
            }
        }
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
        }.cancellable(id: CancelID.holdings(bookID), cancelInFlight: true)
    }

    private func focus(_ shelves: [IndoorShelfLabel], state: inout State) {
        // 층이 여러 개면 현재 표시 층을 우선하며, 다른 층의 후보는 개별 버튼으로 이동한다.
        guard let floorID = shelves.first(where: { $0.floorID == state.map.selectedFloorID })?.floorID
                ?? shelves.first?.floorID else { return }
        state.map.selectedFloorID = floorID
        state.map.requestCamera(.features(shelves.filter { $0.floorID == floorID }.map(\.mapElementID)))
    }
}
