import Foundation

struct BookRoutePreviewBookInfo {
    struct Route: Equatable {
        let distanceText: String
        let floorChangeCount: Int
    }

    let holding: BookHolding?
    let shelves: [IndoorShelfLabel]
    let location: String?
    let route: Route?

    var routeSummary: String? {
        route.map { "\($0.distanceText) · 층 이동 \($0.floorChangeCount)회" }
    }

    init(book: Book, holdings: BookShelfMapFeature.HoldingsState?,
         resolutions: [ShelfResolution], map: IndoorMap?, routePlan: RoutePlan?) {
        let stop = routePlan?.stops.first { $0.book.id == book.id }

        let holding: BookHolding?
        if let shelf = stop?.shelf,
           let resolution = resolutions.first(where: { $0.shelves.contains(shelf) }) {
            holding = resolution.holding
        } else if case let .loaded(items) = holdings {
            holding = BookHolding.preferred(in: items)
        } else {
            holding = nil
        }

        let shelves = stop?.candidateShelves ?? resolutions.first { $0.holding == holding }?.shelves ?? []

        if let holding {
            let floorID = stop?.shelf.floorID ?? shelves.first?.floorID
            let floor = map?.floors.first { $0.id == floorID }
            location = BookDetailDestinationPresentation(
                holding: holding, floorText: floor.map { "\($0.ordinal + 1)층" }, shelves: shelves
            ).locationText
        } else {
            location = nil
        }

        if let routePlan, let index = routePlan.stops.firstIndex(where: { $0.book.id == book.id }) {
            let legs = routePlan.legs.prefix(index + 1)
            let distance = legs.reduce(0) { $0 + $1.distanceMeters }
            let floorChanges = legs.reduce(0) { $0 + $1.floorChanges.count }
            let estimated = legs.contains { $0.usesEstimatedDistances } ? "약 " : ""
            route = Route(
                distanceText: "\(estimated)\(distance.formatted(.number.precision(.fractionLength(0))))m",
                floorChangeCount: floorChanges)
        } else {
            route = nil
        }

        self.holding = holding
        self.shelves = shelves
    }
}
