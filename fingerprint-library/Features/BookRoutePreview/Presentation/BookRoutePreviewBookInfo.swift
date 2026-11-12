import Foundation

// ✅ 여러 권 미리보기의 접힌 카드와 펼친 상세 화면이 같은 기준으로 대표 소장본·위치·경로 요약을 계산한다.
// ✅ 기존 BookRoutePreviewBookCard의 계산 프로퍼티를 그대로 옮겼다.
struct BookRoutePreviewBookInfo {
    struct Route: Equatable {
        let distanceText: String
        let floorChangeCount: Int
    }

    let holding: BookHolding?
    let shelves: [IndoorShelfLabel]
    let location: String?
    /// 경로 시작부터 이 책까지의 누적 거리와 층 이동 횟수.
    let route: Route?

    var routeSummary: String? {
        route.map { "\($0.distanceText) · 층 이동 \($0.floorChangeCount)회" }
    }

    init(book: Book, holdings: BookShelfMapFeature.HoldingsState?,
         resolutions: [ShelfResolution], map: IndoorMap?, session: RoutePlan?) {
        let stop = session?.stops.first { $0.book.id == book.id }

        let holding: BookHolding?
        if let shelf = stop?.shelf,
           let resolution = resolutions.first(where: { $0.shelves.contains(shelf) }) {
            holding = resolution.holding
        } else if case let .loaded(items) = holdings {
            holding = BookHoldingPresentation.preferred(in: items)
        } else {
            holding = nil
        }

        // 지도와 같은 대표 소장본의 위치만 표시한다.
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

        if let session, let index = session.stops.firstIndex(where: { $0.book.id == book.id }) {
            let legs = session.legs.prefix(index + 1)
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
