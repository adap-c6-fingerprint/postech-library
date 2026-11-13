import Foundation

struct RouteStop: Equatable, Sendable {
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

    var candidateStop: RouteCandidateStop {
        .init(book: book, holdings: holdings, candidateShelves: candidateShelves)
    }
}

struct RoutePlan: Identifiable, Equatable, Sendable {
    let id = UUID()
    let map: IndoorMap
    let shelfLabels: [IndoorShelfLabel]
    let stops: [RouteStop]
    let legs: [IndoorRoute]
    let graph: RoutingGraph
    let start: IndoorPosition
    let route: IndoorRoute
    let guidance: RoutePreviewGuidance

    init(map: IndoorMap, shelfLabels: [IndoorShelfLabel], stops: [RouteStop],
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

    func matches(candidates: [RouteCandidateStop]) -> Bool {
        stops.count == candidates.count
            && stops.allSatisfy { candidates.contains($0.candidateStop) }
    }
}
