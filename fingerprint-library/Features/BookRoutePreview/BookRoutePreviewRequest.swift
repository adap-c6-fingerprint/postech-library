import Foundation

enum BookRoutePreviewRequest: Equatable {
    case waiting
    case failed(String)
    case ready(map: IndoorMap, labels: [IndoorShelfLabel], start: IndoorPosition, stops: [RouteCandidateStop])

    init(state: BookShelfMapFeature.State?, start: IndoorPosition? = nil) {
        guard let state else { self = .waiting; return }
        if let error = state.map.loadError ?? state.map.shelfLabelError {
            self = .failed(error); return
        }
        var stops: [RouteCandidateStop] = []
        for book in state.books {
            switch state.holdings[book.id] {
            case nil, .idle, .loading: self = .waiting; return
            case .failed(let message): self = .failed(message); return
            case .loaded(let holdings):
                guard state.map.map != nil, !state.map.isLoading, !state.map.isLoadingShelfLabels,
                      state.resolutions[book.id] != nil else { self = .waiting; return }
                let shelves = state.shelves(for: book.id)
                guard ShelfOverlapPolicy().allows(shelves) else {
                    self = .failed("\(BookText.plainText(book.title)): 안내할 서가 후보를 확인할 수 없어 경로를 계산하지 않았어요.")
                    return
                }
                stops.append(.init(book: book, holdings: holdings, candidateShelves: shelves))
            }
        }
        guard let map = state.map.map, !stops.isEmpty else { self = .waiting; return }
        guard let start else {
            self = .failed(IndoorRoutingError.invalidPosition.localizedDescription); return
        }
        guard let ordinal = start.floorOrdinal, map.floors.contains(where: { $0.ordinal == ordinal }) else {
            self = .failed(IndoorRoutingError.unknownFloor.localizedDescription); return
        }
        self = .ready(map: map, labels: state.map.shelfLabels, start: start, stops: stops)
    }
}
