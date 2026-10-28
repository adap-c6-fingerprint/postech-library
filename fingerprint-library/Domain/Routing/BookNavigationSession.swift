import Foundation

/// 입력 도서 순서의 방문 목적지. 원본 도서·소장 정보와 실제 서가를 함께 보존한다.
struct BookNavigationStop: Equatable, Sendable {
    let book: Book
    let holdings: [BookHolding]
    let shelf: IndoorShelfLabel
}

/// 미리보기에서 확정한 안내 입력 스냅샷. 실시간 위치·진행 단계는 수신 화면에서 구현한다.
struct BookNavigationSession: Identifiable, Equatable, Sendable {
    let id = UUID()
    let map: IndoorMap
    let shelfLabels: [IndoorShelfLabel]
    let stops: [BookNavigationStop]
    let legs: [IndoorRoute]
    let graph: RoutingGraph
    let origin: IndoorShelfLabel
    let start: IndoorPosition
    let route: IndoorRoute
    let guidance: RoutePreviewGuidance

    init(map: IndoorMap, shelfLabels: [IndoorShelfLabel], stops: [BookNavigationStop],
         legs: [IndoorRoute], graph: RoutingGraph, origin: IndoorShelfLabel, start: IndoorPosition) throws {
        guard BookRouteSelection.allows(bookCount: stops.count),
              Set(stops.map { $0.book.id }).count == stops.count,
              stops.count == legs.count, let first = legs.first, let last = legs.last else {
            throw IndoorRoutingError.invalidDestination
        }
        for (index, leg) in legs.enumerated() {
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
            usesEstimatedDistances: legs.contains { $0.usesEstimatedDistances }, start: first.start)
        self.map = map
        self.shelfLabels = shelfLabels
        self.stops = stops
        self.legs = legs
        self.graph = graph
        self.origin = origin
        self.start = start
        self.route = route
        guidance = try RoutePreviewGuidance(route: route, graph: graph)
    }
}
