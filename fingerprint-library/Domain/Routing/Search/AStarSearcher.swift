import Foundation

/// Fingerprint의 heap·best-cost 갱신·동률 순서를 유지하고 시간 비용을 거리로 전환했다.
nonisolated struct AStarSearcher: Sendable {
    let index: RoutingGraphIndex

    func search(from start: String, to destination: String, excludingStairs: Bool) throws -> [RouteTraversal]? {
        guard let origin = index.nodesByID[start], let target = index.nodesByID[destination] else {
            throw IndoorRoutingError.invalidGraph
        }
        if start == destination { return [] }
        struct Entry {
            let id: String
            let distance: Double
            let estimate: Double
            let order: Int
        }
        var order = 0
        var queue = BinaryHeap<Entry> { lhs, rhs in
            if lhs.estimate != rhs.estimate { return lhs.estimate < rhs.estimate }
            if lhs.distance != rhs.distance { return lhs.distance < rhs.distance }
            if lhs.id != rhs.id { return lhs.id < rhs.id }
            return lhs.order < rhs.order
        }
        queue.insert(
            Entry(
                id: start, distance: 0,
                estimate: RoutingGeometry.distanceMeters(from: origin.coordinate, to: target.coordinate), order: order))
        var best = [start: 0.0]
        var previous: [String: RouteTraversal] = [:]
        while let entry = queue.pop() {
            try Task.checkCancellation()
            guard entry.distance == best[entry.id] else { continue }
            if entry.id == destination {
                var path: [RouteTraversal] = []
                var current = destination
                while current != start {
                    guard let arc = previous[current], path.count < index.nodesByID.count else {
                        throw IndoorRoutingError.invalidGraph
                    }
                    path.append(arc)
                    current = arc.fromNodeID
                }
                return Array(path.reversed())
            }
            for arc in index.outgoing[entry.id, default: []] {
                if excludingStairs && arc.category == .stairs { continue }
                let candidate = entry.distance + arc.distanceMeters
                guard candidate.isFinite, candidate < best[arc.toNodeID, default: .infinity],
                    let node = index.nodesByID[arc.toNodeID]
                else { continue }
                best[arc.toNodeID] = candidate
                previous[arc.toNodeID] = arc
                order += 1
                queue.insert(
                    .init(
                        id: node.id, distance: candidate,
                        estimate: candidate
                            + RoutingGeometry.distanceMeters(from: node.coordinate, to: target.coordinate), order: order
                    ))
            }
        }
        return nil
    }
}
