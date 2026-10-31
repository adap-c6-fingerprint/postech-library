//
//  BookRoutePlanner.swift
//  fingerprint-library
//
//  Created by Youngmin Cho on 10/31/26.
//

import Foundation

/// 파일 접근 없이, 준비된 자료로 최단 방문 순서와 안내 세션을 만듦
nonisolated struct BookRoutePlanner {
    @concurrent
    func plan(_ input: BookRoutePlanningInput) async throws -> BookNavigationSession {
        let selections = await MainActor.run {
            input.stops.map {
                (
                    bookID: $0.book.id,
                    shelf: $0.shelf
                )
            }
        }
        guard BookRouteSelection.allows(bookCount: selections.count),
              Set(selections.map(\.bookID)).count == selections.count else {
            throw IndoorRoutingError.invalidDestination
        }
        
        let orders: [[Int]] = switch selections.count {
        case 1: [[0]]
        case 2: [[0, 1], [1, 0]]
        case 3: [[0, 1, 2], [0, 2, 1], [1, 0, 2], [1, 2, 0], [2, 0, 1], [2, 1, 0]]
        default: throw IndoorRoutingError.invalidDestination
        }
        
        var cache: [LegKey: IndoorRoute] = [:]
        var unreachable = Set<LegKey>()
        var bestOrder: [Int] = []
        var bestLegs: [IndoorRoute] = []
        var bestDistance = Double.infinity
        
        for order in orders {
            try Task.checkCancellation()
            var legs: [IndoorRoute] = []
            do {
                for (index, next) in order.enumerated() {
                    try Task.checkCancellation()
                    let previous = index == 0 ? -1 : order[index - 1]
                    let key = LegKey(from: previous, to: next)
                    if unreachable.contains(key) { throw IndoorRoutingError.noRoute }
                    if let cached = cache[key] {
                        legs.append(cached)
                    } else {
                        do {
                            let start = previous == -1 ? input.start : try position(
                                at: selections[previous].shelf,
                                in: input.navigation,
                                timestamp: input.start.timestamp
                            )
                            let goal = try destination(
                                for: selections[next].shelf, in: input.navigation
                            )
                            let leg = try route(from: start, to: goal.key, in: input.navigation)
                            cache[key] = leg
                            legs.append(leg)
                        } catch IndoorRoutingError.noRoute {
                            unreachable.insert(key)
                            throw IndoorRoutingError.noRoute
                        }
                    }
                }
            } catch IndoorRoutingError.noRoute {
                continue
            }
            let distance = legs.reduce(0) { $0 + $1.distanceMeters }
            // 동률이면 기존 입력 기준의 먼저 열거한 순서를 유지
            if distance < bestDistance {
                bestDistance = distance
                bestOrder = order
                bestLegs = legs
            }
        }
        guard !bestLegs.isEmpty else { throw IndoorRoutingError.noRoute }
        try Task.checkCancellation()
        return try await BookNavigationSession(
            map: input.map,
            shelfLabels: input.shelfLabels,
            stops: bestOrder.map { input.stops[$0] },
            legs: bestLegs,
            graph: input.navigation.graph,
            origin: input.origin,
            start: input.start
        )
    }
    
    func route(
        from start: IndoorPosition,
        to destination: ShelfKey,
        in navigation: IndoorNavigationData
    ) throws -> IndoorRoute {
        let outcome = try IndoorRouteSearchEngine().search(.init(
            navigation: navigation,
            start: start,
            destination: destination,
            preference: .shortestDistance
        ))
        guard case .route(let route) = outcome else {
            throw IndoorRoutingError.noRoute
        }
        return route
    }
    
    private func destination(
        for shelf: IndoorShelfLabel, in navigation: IndoorNavigationData
    ) throws -> ShelfDestination {
        let key = ShelfKey(datasetID: navigation.shelves.datasetID, value: shelf.fixtureNumber)
        guard let destination = try? navigation.shelves.destination(for: key),
              destination.mapElementID == shelf.mapElementID,
              destination.floorID == shelf.floorID else {
            throw IndoorRoutingError.invalidDestination
        }
        return destination
    }
    
    private func position(
        at shelf: IndoorShelfLabel, in navigation: IndoorNavigationData, timestamp: Date
    ) throws -> IndoorPosition {
        let destination = try destination(for: shelf, in: navigation)
        guard let node = navigation.graph.nodes.first(where: { $0.id == destination.arrivalNodeID }),
              node.floorID == destination.floorID,
              node.coordinate == destination.arrivalCoordinate else {
            throw IndoorRoutingError.invalidDestination
        }
        return IndoorPosition(
            coordinate: node.coordinate, floorOrdinal: node.level,
            horizontalAccuracy: nil, timestamp: timestamp, source: .manual
        )
    }
    
    private struct LegKey: Hashable {
        let from: Int
        let to: Int
    }
}
