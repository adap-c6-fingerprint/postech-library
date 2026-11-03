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
        guard let holding = BookHoldingPresentation.preferred(in: holdings) else { return nil }
        guard let context, let map = context.map else {
            return Self(holding: holding, floorText: nil, shelves: [])
        }
        let shelves = BookHoldingShelfResolver().resolve([holding], on: map, labels: context.labels)
            .flatMap(\.shelves).sorted { $0.id < $1.id }
        let floor = shelves.first.flatMap { shelf in map.floors.first { $0.id == shelf.floorID } }
        return Self(holding: holding, floorText: floor.map { "\($0.ordinal + 1)층" }, shelves: shelves)
    }

    var locationText: String? {
        var seen = Set<String>()
        let numbers = shelves.map(\.realNumber).filter { !$0.isEmpty && seen.insert($0).inserted }
        if let floorText, !numbers.isEmpty {
            let suffix = numbers.count > 1 ? " (후보)" : ""
            return "\(floorText) \(numbers.joined(separator: "·"))번 서가\(suffix)"
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
