import Foundation

/// 기존 소장 조회·서가 해석이 완료된 입력만 경로 계산에 넘긴다.
enum BookRoutePreviewRequest: Equatable {
    case waiting
    case failed(String)
    case ready(map: IndoorMap, labels: [IndoorShelfLabel], stops: [BookNavigationStop])

    init(state: BookShelfMapFeature.State?) {
        guard let state else { self = .waiting; return }
        if let error = state.map.loadError ?? state.map.shelfLabelError {
            self = .failed(error); return
        }
        var stops: [BookNavigationStop] = []
        for book in state.books {
            switch state.holdings[book.id] {
            case nil, .loading: self = .waiting; return
            case .failed(let message): self = .failed(message); return
            case .loaded(let holdings):
                guard state.map.map != nil, !state.map.isLoading, !state.map.isLoadingShelfLabels,
                      state.resolutions[book.id] != nil else { self = .waiting; return }
                let shelves = state.shelves(for: book.id)
                guard shelves.count == 1, let shelf = shelves.first else {
                    self = .failed("\(BookText.plainText(book.title)): 서가 한 곳을 확정할 수 없어 경로를 계산하지 않았어요.")
                    return
                }
                stops.append(.init(book: book, holdings: holdings, shelf: shelf))
            }
        }
        guard let map = state.map.map, !stops.isEmpty else { self = .waiting; return }
        self = .ready(map: map, labels: state.map.shelfLabels, stops: stops)
    }
}
