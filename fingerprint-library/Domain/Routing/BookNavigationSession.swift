import Foundation

/// 입력 도서 순서의 방문 목적지. 원본 도서·소장 정보와 실제 서가를 함께 보존한다.
struct BookNavigationStop: Equatable, Sendable {
    let book: Book
    let holdings: [BookHolding]
    let shelf: IndoorShelfLabel
    let candidateShelves: [IndoorShelfLabel]

    init(book: Book, holdings: [BookHolding], shelf: IndoorShelfLabel,
         candidateShelves: [IndoorShelfLabel]? = nil) {
        self.book = book
        self.holdings = holdings
        self.shelf = shelf
        self.candidateShelves = (candidateShelves ?? [shelf]).sorted { $0.fixtureNumber < $1.fixtureNumber }
    }

    var candidateStop: BookRouteCandidateStop {
        .init(book: book, holdings: holdings, candidateShelves: candidateShelves)
    }
}

/// 미리보기에서 확정한 안내 입력 스냅샷. 실시간 위치·진행 단계는 수신 화면에서 구현한다.
struct BookNavigationSession: Identifiable, Equatable, Sendable {
    let id = UUID()
    let map: IndoorMap
    let shelfLabels: [IndoorShelfLabel]
    let stops: [BookNavigationStop]
    let legs: [IndoorRoute]
    let graph: RoutingGraph
    let start: IndoorPosition
    let route: IndoorRoute
    let guidance: RoutePreviewGuidance

    init(map: IndoorMap, shelfLabels: [IndoorShelfLabel], stops: [BookNavigationStop],
         legs: [IndoorRoute], graph: RoutingGraph, start: IndoorPosition) throws {
        guard BookRouteSelection.allows(bookCount: stops.count),
              Set(stops.map { $0.book.id }).count == stops.count,
              stops.count == legs.count, let first = legs.first, let last = legs.last else {
            throw IndoorRoutingError.invalidDestination
        }
        for (index, leg) in legs.enumerated() {
            guard ShelfOverlapPolicy().allows(stops[index].candidateShelves),
                  stops[index].candidateShelves.contains(stops[index].shelf) else {
                throw IndoorRoutingError.invalidDestination
            }
            guard leg.destination.value == stops[index].shelf.fixtureNumber,
                  index == 0 || legs[index - 1].nodeIDs.last == leg.nodeIDs.first else {
                throw IndoorRoutingError.invalidGraph
            }
        }
        let route = IndoorRoute(
            destination: last.destination,
            nodeIDs: first.nodeIDs + legs.dropFirst().flatMap { $0.nodeIDs.dropFirst() },
            edgeIDs: legs.flatMap { $0.edgeIDs }, segments: legs.flatMap { $0.segments },
            floorChanges: legs.flatMap { $0.floorChanges },
            distanceMeters: legs.reduce(0) { $0 + $1.distanceMeters },
            usesEstimatedDistances: legs.contains { $0.usesEstimatedDistances }, start: first.start,
            edgeDistancesMeters: legs.allSatisfy { $0.edgeDistancesMeters != nil }
                ? legs.flatMap { $0.edgeDistancesMeters ?? [] } : nil)
        self.map = map
        self.shelfLabels = shelfLabels
        self.stops = stops
        self.legs = legs
        self.graph = graph
        self.start = start
        self.route = route
        guidance = try RoutePreviewGuidance(route: route, graph: graph)
    }

    /// 방문 순서·목적지를 골라도 원본 책·소장·후보가 같은 계산 결과만 사용한다.
    func matches(candidates: [BookRouteCandidateStop]) -> Bool {
        stops.count == candidates.count
            && stops.allSatisfy { candidates.contains($0.candidateStop) }
    }
}
