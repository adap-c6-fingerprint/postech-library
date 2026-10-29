import Foundation

nonisolated enum RouteManeuver: Equatable, Sendable {
    case straight, left, right, turnAround, nearDestination
    case changeFloor(RouteEdgeCategory, to: UUID)
}

nonisolated struct RouteGuidanceProgress: Equatable, Sendable {
    let stepIndex: Int
    let fraction: Double
    let distanceAlongRoute: Double
    let coordinate: IndoorMapCoordinate
    let maneuver: RouteManeuver
    let distanceToManeuver: Double?
    /// 층간 구간별 거리 근거가 부족하면 값을 만들지 않는다.
    let remainingMeters: Double?
}

nonisolated enum RouteGuidanceError: Error, Equatable, Sendable {
    case invalidRoute, invalidPosition, inaccuratePosition, stalePosition, unknownFloor, offRoute, ambiguousPosition
}

/// 확정된 경로의 순서를 유지하며 위치를 경로에 투영한다. 탐색·실제 측위·도착 확정은 하지 않는다.
nonisolated struct RouteGuidancePlan: Equatable, Sendable {
    // 실내 통로 안내용 초기 정책값. 실측 보정 결과나 측위 정확도 보장을 뜻하지 않는다.
    static let maximumPositionAge: Double = 10
    static let maximumAccuracyMeters: Double = 10
    static let matchingRadiusMeters: Double = 5

    struct Step: Equatable, Sendable {
        let from: RouteNode
        let to: RouteNode
        let category: RouteEdgeCategory
        let groupID: UUID?
        let coordinates: [IndoorMapCoordinate]
        var meters: Double?
        var startDistance: Double = 0
        var changesFloor: Bool { from.floorID != to.floorID }
    }

    struct Instruction: Equatable, Sendable {
        let stepIndex: Int
        let maneuver: RouteManeuver
    }

    let steps: [Step]
    let instructions: [Instruction]
    let destination: RouteNode

    init(route: IndoorRoute, graph: RoutingGraph) throws {
        guard route.distanceMeters.isFinite, route.distanceMeters >= 0,
              Set(graph.nodes.map(\.id)).count == graph.nodes.count,
              Set(graph.edges.map(\.id)).count == graph.edges.count,
              let lastID = route.nodeIDs.last,
              let destination = graph.nodes.first(where: { $0.id == lastID }) else {
            throw RouteGuidanceError.invalidRoute
        }
        let nodes = Dictionary(uniqueKeysWithValues: graph.nodes.map { ($0.id, $0) })
        let edges = Dictionary(uniqueKeysWithValues: graph.edges.map { ($0.id, $0) })
        let projectedStart = route.nodeIDs.count == route.edgeIDs.count && !route.edgeIDs.isEmpty
        guard projectedStart || route.nodeIDs.count == route.edgeIDs.count + 1 else {
            throw RouteGuidanceError.invalidRoute
        }
        let arrivals = projectedStart ? route.nodeIDs : Array(route.nodeIDs.dropFirst())
        var pieces: [Step] = []
        for (index, id) in route.edgeIDs.enumerated() {
            guard let edge = edges[id], let to = nodes[arrivals[index]],
                  let originalFrom = nodes[edge.fromNodeID], let originalTo = nodes[edge.toNodeID],
                  edge.coordinates.count >= 2, edge.coordinates.allSatisfy(\.isValid),
                  edge.coordinates.first == originalFrom.coordinate,
                  edge.coordinates.last == originalTo.coordinate else { throw RouteGuidanceError.invalidRoute }
            let from: RouteNode
            var coordinates: [IndoorMapCoordinate]
            if to.id == edge.toNodeID {
                from = originalFrom
                coordinates = edge.coordinates
            } else if to.id == edge.fromNodeID, edge.direction == .undirected {
                from = originalTo
                coordinates = Array(edge.coordinates.reversed())
            } else { throw RouteGuidanceError.invalidRoute }
            if index == 0, projectedStart {
                guard from.floorID == to.floorID, from.floorID == route.start.floorID else {
                    throw RouteGuidanceError.invalidRoute
                }
                coordinates = try Self.clipped(coordinates, at: route.start.routeCoordinate)
            } else {
                let expected = index == 0 ? route.nodeIDs.first : arrivals[index - 1]
                guard from.id == expected else { throw RouteGuidanceError.invalidRoute }
            }
            let changesFloor = from.floorID != to.floorID
            if changesFloor, edge.category == .walkway { throw RouteGuidanceError.invalidRoute }
            pieces.append(.init(from: from, to: to, category: edge.category, groupID: edge.groupID,
                coordinates: coordinates, meters: changesFloor ? nil : RoutingGeometry.polylineLengthMeters(coordinates)))
        }
        let horizontal = pieces.compactMap(\.meters).reduce(0, +)
        guard horizontal <= route.distanceMeters + 0.1 else { throw RouteGuidanceError.invalidRoute }
        let transitions = pieces.indices.filter { pieces[$0].changesFloor }
        // 층간 간선이 하나면 전체 비용에서 평면 길이를 빼 잔여 비용을 복원할 수 있다.
        // 여러 간선의 개별 비용은 IndoorRoute에 없으므로 임의로 나눠 넣지 않는다.
        if transitions.count == 1 {
            pieces[transitions[0]].meters = max(0, route.distanceMeters - horizontal)
        }
        var distance = 0.0
        for index in pieces.indices {
            pieces[index].startDistance = distance
            distance += pieces[index].meters ?? 0
        }
        self.steps = pieces
        self.destination = destination
        self.instructions = Self.makeInstructions(pieces)
    }

    func progress(for position: IndoorPosition, at now: Date,
                  previous: RouteGuidanceProgress? = nil, elapsed: Double? = nil) throws -> RouteGuidanceProgress {
        guard position.source != .manual, position.coordinate.isValid,
              let accuracy = position.horizontalAccuracy, accuracy.isFinite, accuracy >= 0 else {
            throw RouteGuidanceError.invalidPosition
        }
        guard (-2...Self.maximumPositionAge).contains(now.timeIntervalSince(position.timestamp)) else {
            throw RouteGuidanceError.stalePosition
        }
        guard accuracy <= Self.maximumAccuracyMeters else { throw RouteGuidanceError.inaccuratePosition }
        guard let level = position.floorOrdinal else { throw RouteGuidanceError.unknownFloor }
        if steps.isEmpty {
            guard level == destination.level else { throw RouteGuidanceError.unknownFloor }
            guard RoutingGeometry.distanceMeters(from: position.coordinate, to: destination.coordinate) <= 2 else {
                throw RouteGuidanceError.offRoute
            }
            return .init(stepIndex: 0, fraction: 1, distanceAlongRoute: 0, coordinate: destination.coordinate,
                         maneuver: .nearDestination, distanceToManeuver: 0, remainingMeters: 0)
        }
        struct Candidate {
            let index: Int
            let fraction: Double
            let coordinate: IndoorMapCoordinate
            let offset: Double
            let distance: Double
        }
        var candidates: [Candidate] = []
        for (index, step) in steps.enumerated() {
            if step.changesFloor {
                for (node, fraction) in [(step.from, 0.0), (step.to, 1.0)] where node.level == level {
                    candidates.append(.init(index: index, fraction: fraction, coordinate: node.coordinate,
                        offset: step.startDistance + fraction * (step.meters ?? 0),
                        distance: RoutingGeometry.distanceMeters(from: position.coordinate, to: node.coordinate)))
                }
            } else if step.from.level == level {
                let projection = Self.projection(position.coordinate, onto: step.coordinates)
                candidates.append(.init(index: index, fraction: projection.fraction, coordinate: projection.point,
                    offset: step.startDistance + projection.fraction * (step.meters ?? 0), distance: projection.distance))
            }
        }
        guard let closest = candidates.map(\.distance).min() else { throw RouteGuidanceError.unknownFloor }
        guard closest <= Self.matchingRadiusMeters else { throw RouteGuidanceError.offRoute }
        // 가까운 평행 통로·경로 교차점에서 가장 가까운 좌표만으로 뒷구간에 점프하지 않는다.
        candidates = candidates.filter { $0.distance <= min(Self.matchingRadiusMeters, closest + max(0.25, min(accuracy, 1))) }
        if let previous {
            let limit = max(8, min(elapsed ?? 0, Self.maximumPositionAge) * 3 + accuracy)
            candidates = candidates.filter { abs($0.offset - previous.distanceAlongRoute) <= limit }
            guard !candidates.isEmpty else { throw RouteGuidanceError.ambiguousPosition }
            candidates.sort {
                let lhs = abs(Double($0.index) + $0.fraction - Double(previous.stepIndex) - previous.fraction)
                let rhs = abs(Double($1.index) + $1.fraction - Double(previous.stepIndex) - previous.fraction)
                return lhs == rhs ? $0.distance < $1.distance : lhs < rhs
            }
        } else {
            candidates.sort { $0.distance == $1.distance ? $0.index < $1.index : $0.distance < $1.distance }
            if let first = candidates.first, candidates.contains(where: {
                abs($0.offset - first.offset) > 8 && abs($0.index - first.index) > 1
            }) { throw RouteGuidanceError.ambiguousPosition }
        }
        guard let match = candidates.first else { throw RouteGuidanceError.offRoute }
        let step = steps[match.index]
        let remaining: Double? = steps.indices.dropFirst(match.index).reduce(Optional(0.0)) { result, index in
            if index == match.index, match.fraction >= 1 { return result }
            guard let result, let meters = steps[index].meters else { return nil }
            return result + meters * (index == match.index ? 1 - match.fraction : 1)
        }
        let order = Double(match.index) + match.fraction
        let upcoming = instructions.first { Double($0.stepIndex) >= order - 0.000_001 }
        let nearDestination = match.index == steps.count - 1 && (!step.changesFloor || match.fraction >= 1)
            && (remaining ?? .infinity) <= 2 && match.distance <= 2
        let maneuver: RouteManeuver
        let toManeuver: Double?
        if nearDestination {
            maneuver = .nearDestination
            toManeuver = remaining
        } else if step.changesFloor, match.fraction < 1 {
            maneuver = floorInstruction(at: match.index)
            toManeuver = 0
        } else if let upcoming {
            maneuver = upcoming.maneuver
            let before = steps[match.index..<upcoming.stepIndex]
            toManeuver = before.contains(where: { $0.changesFloor }) ? nil
                : max(0, steps[upcoming.stepIndex].startDistance - match.offset)
        } else {
            maneuver = .straight
            toManeuver = remaining
        }
        return .init(stepIndex: match.index, fraction: match.fraction, distanceAlongRoute: match.offset,
            coordinate: match.coordinate, maneuver: maneuver, distanceToManeuver: toManeuver, remainingMeters: remaining)
    }

    private func floorInstruction(at index: Int) -> RouteManeuver {
        var last = index
        while last + 1 < steps.count, steps[last + 1].changesFloor,
              steps[last + 1].category == steps[index].category,
              steps[last].to.id == steps[last + 1].from.id,
              (steps[last].to.level > steps[last].from.level) == (steps[last + 1].to.level > steps[last + 1].from.level) {
            last += 1
        }
        return .changeFloor(steps[index].category, to: steps[last].to.floorID)
    }

    private static func makeInstructions(_ steps: [Step]) -> [Instruction] {
        var result: [Instruction] = []
        for index in steps.indices {
            let step = steps[index]
            if step.changesFloor {
                if index > 0, steps[index - 1].changesFloor,
                   steps[index - 1].category == step.category,
                   (steps[index - 1].to.level > steps[index - 1].from.level) == (step.to.level > step.from.level) { continue }
                var last = index
                while last + 1 < steps.count, steps[last + 1].changesFloor,
                      steps[last + 1].category == step.category,
                      (steps[last].to.level > steps[last].from.level) == (steps[last + 1].to.level > steps[last + 1].from.level) {
                    last += 1
                }
                result.append(.init(stepIndex: index, maneuver: .changeFloor(step.category, to: steps[last].to.floorID)))
            } else if index > 0, !steps[index - 1].changesFloor {
                let previous = steps[index - 1]
                if let group = step.groupID, group == previous.groupID { continue }
                guard let incoming = vector(previous.coordinates, fromEnd: true),
                      let outgoing = vector(step.coordinates, fromEnd: false) else { continue }
                let angle = atan2(incoming.x * outgoing.y - incoming.y * outgoing.x,
                                  incoming.x * outgoing.x + incoming.y * outgoing.y) * 180 / .pi
                guard abs(angle) >= 25 else { continue }
                let maneuver: RouteManeuver = abs(angle) >= 155 ? .turnAround : (angle > 0 ? .left : .right)
                result.append(.init(stepIndex: index, maneuver: maneuver))
            }
        }
        return result
    }

    private static func vector(_ coordinates: [IndoorMapCoordinate], fromEnd: Bool) -> (x: Double, y: Double)? {
        let pairs = Array(zip(coordinates, coordinates.dropFirst()))
        for (a, b) in fromEnd ? Array(pairs.reversed()) : pairs {
            let x = (b.longitude - a.longitude) * cos((a.latitude + b.latitude) / 2 * .pi / 180)
            let y = b.latitude - a.latitude
            let length = hypot(x, y)
            if length > 1e-12 { return (x / length, y / length) }
        }
        return nil
    }

    private static func projection(_ point: IndoorMapCoordinate, onto coordinates: [IndoorMapCoordinate])
        -> (point: IndoorMapCoordinate, fraction: Double, distance: Double, segment: Int) {
        let total = RoutingGeometry.polylineLengthMeters(coordinates)
        var walked = 0.0
        var best = (point: coordinates[0], fraction: 0.0, distance: Double.infinity, segment: 0)
        for index in 0..<(coordinates.count - 1) {
            let a = coordinates[index], b = coordinates[index + 1]
            let scale = cos((a.latitude + b.latitude + point.latitude) / 3 * .pi / 180)
            let x = (b.longitude - a.longitude) * scale, y = b.latitude - a.latitude
            let squared = x * x + y * y
            let fraction = squared > 0 ? min(1, max(0,
                ((point.longitude - a.longitude) * scale * x + (point.latitude - a.latitude) * y) / squared)) : 0
            let projected = IndoorMapCoordinate(latitude: a.latitude + fraction * y,
                longitude: a.longitude + fraction * (b.longitude - a.longitude))
            let length = RoutingGeometry.distanceMeters(from: a, to: b)
            let distance = RoutingGeometry.distanceMeters(from: point, to: projected)
            if distance < best.distance {
                best = (projected, total > 0 ? (walked + fraction * length) / total : 0, distance, index)
            }
            walked += length
        }
        return best
    }

    private static func clipped(_ coordinates: [IndoorMapCoordinate], at start: IndoorMapCoordinate) throws -> [IndoorMapCoordinate] {
        guard start.isValid else { throw RouteGuidanceError.invalidRoute }
        let projection = projection(start, onto: coordinates)
        guard projection.distance < 0.1 else { throw RouteGuidanceError.invalidRoute }
        return [projection.point] + coordinates.dropFirst(projection.segment + 1)
    }
}
