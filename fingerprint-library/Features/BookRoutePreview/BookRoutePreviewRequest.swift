import Foundation

nonisolated enum RouteFailure: Equatable, Sendable {
    case routing(IndoorRoutingError)
    case mapUnavailable(String)
    case holdingsUnavailable(String)
    case ambiguousShelf(bookTitle: String)
    case unexpected(String)

    init(error: any Error) {
        if let routing = error as? IndoorRoutingError {
            self = .routing(routing)
        } else {
            self = .unexpected(error.localizedDescription)
        }
    }

    var message: String {
        switch self {
        case let .routing(error): error.localizedDescription
        case let .mapUnavailable(message), let .holdingsUnavailable(message), let .unexpected(message): message
        case let .ambiguousShelf(title): "\(title): 안내할 서가 후보를 확인할 수 없어 경로를 계산하지 않았어요."
        }
    }

    var diagnosticCode: String {
        switch self {
        case let .routing(error): String(describing: error)
        case .mapUnavailable: "map_unavailable"
        case .holdingsUnavailable: "holdings_unavailable"
        case .ambiguousShelf: "ambiguous_shelf"
        case .unexpected: "unexpected"
        }
    }
}

enum BookRoutePreviewRequest: Equatable {
    case waiting
    case failed(RouteFailure)
    case ready(map: IndoorMap, labels: [IndoorShelfLabel], start: IndoorPosition, stops: [RouteCandidateStop])

    init(state: BookShelfMapFeature.State?, start: IndoorPosition? = nil) {
        guard let state else { self = .waiting; return }
        if let error = state.map.loadError ?? state.map.shelfLabelError {
            self = .failed(.mapUnavailable(error)); return
        }
        var stops: [RouteCandidateStop] = []
        for book in state.books {
            switch state.holdings[book.id] {
            case nil, .idle, .loading: self = .waiting; return
            case .failed(let message): self = .failed(.holdingsUnavailable(message)); return
            case .loaded(let holdings):
                guard state.map.map != nil, !state.map.isLoading, !state.map.isLoadingShelfLabels,
                      state.resolutions[book.id] != nil else { self = .waiting; return }
                let shelves = state.shelves(for: book.id)
                guard ShelfOverlapPolicy().allows(shelves) else {
                    self = .failed(.ambiguousShelf(bookTitle: BookText.plainText(book.title)))
                    return
                }
                stops.append(.init(book: book, holdings: holdings, candidateShelves: shelves))
            }
        }
        guard let map = state.map.map, !stops.isEmpty else { self = .waiting; return }
        guard let start else {
            self = .failed(.routing(.invalidPosition)); return
        }
        guard let ordinal = start.floorOrdinal, map.floors.contains(where: { $0.ordinal == ordinal }) else {
            self = .failed(.routing(.unknownFloor)); return
        }
        self = .ready(map: map, labels: state.map.shelfLabels, start: start, stops: stops)
    }
}
