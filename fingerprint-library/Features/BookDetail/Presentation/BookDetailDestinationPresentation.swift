import Foundation

/// 현재 앱 지도 자료만 전달한다. 상세 전용 계산이 공용 지도 경로를 덮어쓰지 않는다.
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
        guard var holding = BookHoldingPresentation.preferred(in: holdings) else { return nil }
        guard let map else {
            return Self(holding: holding, floorText: nil, shelves: [])
        }
        let resolutions = ShelfResolver().resolve(holdings, on: map, labels: labels)
        // 대표 소장본이 2층 삼각서가라도 3·4층 일반 서고에서 서가를 찾았으면 길안내와 같은 일반 서고를 보여 준다.
        if resolutions.first(where: { $0.holding == holding })?.area == .displayShelf {
            let general = resolutions.preferredForRoute.filter { $0.area == .generalStack && !$0.shelves.isEmpty }
            if let preferred = BookHoldingPresentation.preferred(in: general.map(\.holding)) { holding = preferred }
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
            // 2층 삼각서가는 번호가 아니라 이름이라 "번 서가"를 붙이지 않는다.
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
