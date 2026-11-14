import Foundation

nonisolated struct RouteTurnArrow: Identifiable, Equatable, Sendable {
    let stepIndex: Int
    let floorID: UUID
    let maneuver: RouteManeuver
    let coordinates: [IndoorMapCoordinate]
    var id: Int { stepIndex }

    static func make(from plan: GuidanceEngine) -> [Self] {
        plan.instructions.compactMap { instruction in
            let index = instruction.stepIndex
            guard instruction.maneuver == .left || instruction.maneuver == .right,
                  index > 0, plan.steps.indices.contains(index) else { return nil }
            let incoming = plan.steps[index - 1], outgoing = plan.steps[index]
            guard !incoming.changesFloor, !outgoing.changesFloor,
                  incoming.to.floorID == outgoing.from.floorID else { return nil }
            let before = Array(prefix(Array(incoming.coordinates.reversed()), meters: 2).reversed())
            let after = prefix(outgoing.coordinates, meters: 2)
            guard before.count >= 2, after.count >= 2, let tip = after.last else { return nil }
            let previous = after[after.count - 2]
            let scale = cos(tip.latitude * .pi / 180)
            let x = (tip.longitude - previous.longitude) * scale
            let y = tip.latitude - previous.latitude
            let length = hypot(x, y)
            guard length > 1e-12, abs(scale) > 1e-6 else { return nil }
            let unitX = x / length, unitY = y / length
            let size = 0.8 / 111_195.0, angle = 35.0 * .pi / 180
            func wing(_ sign: Double) -> IndoorMapCoordinate {
                .init(latitude: tip.latitude + size * (-unitY * cos(angle) + sign * unitX * sin(angle)),
                      longitude: tip.longitude + size * (-unitX * cos(angle) - sign * unitY * sin(angle)) / scale)
            }
            let path = before + after.dropFirst() + [wing(1), tip, wing(-1)]
            guard path.allSatisfy(\.isValid) else { return nil }
            return Self(stepIndex: index, floorID: outgoing.from.floorID,
                        maneuver: instruction.maneuver, coordinates: path)
        }
    }

    private static func prefix(_ points: [IndoorMapCoordinate], meters: Double) -> [IndoorMapCoordinate] {
        guard let first = points.first else { return [] }
        var result = [first]
        var remaining = meters
        for (a, b) in zip(points, points.dropFirst()) {
            let length = RoutingGeometry.distanceMeters(from: a, to: b)
            guard length > 0 else { continue }
            if length >= remaining {
                let fraction = remaining / length
                result.append(.init(latitude: a.latitude + fraction * (b.latitude - a.latitude),
                                    longitude: a.longitude + fraction * (b.longitude - a.longitude)))
                break
            }
            result.append(b)
            remaining -= length
        }
        return result
    }
}
