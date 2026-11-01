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
                    shelves: $0.candidateShelves
                )
            }
        }
        guard BookRouteSelection.allows(bookCount: selections.count),
              Set(selections.map(\.bookID)).count == selections.count,
              selections.allSatisfy({ ShelfOverlapPolicy().allows($0.shelves) }) else {
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
        var bestShelves: [IndoorShelfLabel] = []
        var bestLegs: [IndoorRoute] = []
        var bestDistance = Double.infinity
        
        for shelves in candidateCombinations(selections.map(\.shelves)) {
            for order in orders {
                try Task.checkCancellation()
                let ordered = order.map { shelves[$0] }
                let legs: [IndoorRoute]
                do {
                    legs = try buildLegs(for: ordered, input: input, cache: &cache, unreachable: &unreachable)
                } catch IndoorRoutingError.noRoute {
                    continue
                }
                let distance = legs.reduce(0) { $0 + $1.distanceMeters }
                // 동률이면 입력 책 순서와 안정화한 후보 ID 순서를 유지한다.
                if distance < bestDistance {
                    bestDistance = distance
                    bestOrder = order
                    bestShelves = shelves
                    bestLegs = legs
                }
            }
        }
        guard !bestLegs.isEmpty else { throw IndoorRoutingError.noRoute }
        try Task.checkCancellation()
        let chosenOrder = bestOrder
        let chosenShelves = bestShelves
        let stops = await MainActor.run {
            chosenOrder.map { input.stops[$0].resolved(at: chosenShelves[$0]) }
        }
        return try await BookNavigationSession(
            map: input.map,
            shelfLabels: input.shelfLabels,
            stops: stops,
            legs: bestLegs,
            graph: input.navigation.graph,
            origin: input.origin,
            start: input.start
        )
    }

    private func candidateCombinations(_ candidates: [[IndoorShelfLabel]]) -> [[IndoorShelfLabel]] {
        candidates.reduce([[]]) { combinations, shelves in
            combinations.flatMap { selected in shelves.map { selected + [$0] } }
        }
    }

    private func buildLegs(for shelves: [IndoorShelfLabel], input: BookRoutePlanningInput,
                           cache: inout [LegKey: IndoorRoute], unreachable: inout Set<LegKey>) throws -> [IndoorRoute] {
        var legs: [IndoorRoute] = []
        for (index, shelf) in shelves.enumerated() {
            try Task.checkCancellation()
            let previous = index == 0 ? nil : shelves[index - 1]
            // 같은 책의 후보가 달라도 다른 구간의 캐시를 재사용하지 않는다.
            let key = LegKey(from: previous?.fixtureNumber, to: shelf.fixtureNumber)
            if unreachable.contains(key) { throw IndoorRoutingError.noRoute }
            if let cached = cache[key] {
                legs.append(cached)
                continue
            }
            do {
                let start = try previous.map {
                    try position(at: $0, in: input.navigation, timestamp: input.start.timestamp)
                } ?? input.start
                let goal = try destination(for: shelf, in: input.navigation)
                let leg = try route(from: start, to: goal.key, in: input.navigation)
                cache[key] = leg
                legs.append(leg)
            } catch IndoorRoutingError.noRoute {
                unreachable.insert(key)
                throw IndoorRoutingError.noRoute
            }
        }
        return legs
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
        let from: String?
        let to: String
    }
}
