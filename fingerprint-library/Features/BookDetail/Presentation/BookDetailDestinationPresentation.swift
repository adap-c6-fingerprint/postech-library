import Foundation

nonisolated struct BookDetailMapContext: Equatable, Sendable {
    let map: IndoorMap?
    let navigation: IndoorNavigationData?
    let labels: [IndoorShelfLabel]
    let position: IndoorPosition?
    let preference: RoutePreference
}

nonisolated struct BookDetailDestinationPresentation: Equatable, Sendable {
    let holding: BookHolding
    let floorText: String?
    let shelves: [IndoorShelfLabel]

    static func resolve(holdings: [BookHolding], context: BookDetailMapContext?) -> Self? {
        resolve(holdings: holdings, map: context?.map, labels: context?.labels ?? [])
    }

    static func resolve(holdings: [BookHolding], map: IndoorMap?, labels: [IndoorShelfLabel]) -> Self? {
        guard var holding = BookHolding.preferred(in: holdings) else { return nil }
        guard let map else {
            return Self(holding: holding, floorText: nil, shelves: [])
        }
        let resolutions = ShelfResolver().resolve(holdings, on: map, labels: labels)
        if resolutions.first(where: { $0.holding == holding })?.area == .displayShelf {
            let general = resolutions.preferredForRoute.filter { $0.area == .generalStack && !$0.shelves.isEmpty }
            if let preferred = BookHolding.preferred(in: general.map(\.holding)) { holding = preferred }
        }
        let shelves = (resolutions.first { $0.holding == holding }?.shelves ?? []).sorted { $0.id < $1.id }
        let floor = shelves.first.flatMap { shelf in map.floors.first { $0.id == shelf.floorID } }
        return Self(holding: holding, floorText: floor.map { "\($0.ordinal + 1)층" }, shelves: shelves)
    }

    var locationText: String? {
        var seen = Set<String>()
        let numbers = shelves.map(\.realNumber).filter { !$0.isEmpty && seen.insert($0).inserted }
        if let floorText, !numbers.isEmpty {
            let suffix = numbers.count > 1 ? " (후보)" : ""
            let names = numbers.joined(separator: "·")
            let shelfText = shelves.allSatisfy(\.isNamedShelf) ? names : "\(names)번 서가"
            return "\(floorText) \(shelfText)\(suffix)"
        }
        let location = holding.locationName?.trimmingCharacters(in: .whitespacesAndNewlines)
        return location?.isEmpty == false ? location : nil
    }
}

nonisolated struct BookDetailRoutePresentation: Equatable, Sendable {
    let distanceMeters: Int
    let floorChangeCount: Int
    let isEstimated: Bool

    init?(route: IndoorRoute) {
        guard route.distanceMeters.isFinite, route.distanceMeters >= 0,
              let meters = Int(exactly: route.distanceMeters.rounded()) else { return nil }
        distanceMeters = meters
        floorChangeCount = route.floorChanges.count
        isEstimated = route.usesEstimatedDistances
    }

    var text: String {
        "\(isEstimated ? "약 " : "")\(distanceMeters)m · 층 이동 \(floorChangeCount)회"
    }
}
