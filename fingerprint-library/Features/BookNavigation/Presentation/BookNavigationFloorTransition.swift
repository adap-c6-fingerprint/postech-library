import Foundation

/// 위치 수신과 독립적으로 사용자가 확인할 수 있는 한 번의 연속 층 이동.
nonisolated struct BookNavigationFloorTransition: Equatable, Sendable, Identifiable {
    let steps: Range<Int>
    let category: RouteEdgeCategory
    let from: RouteNode
    let to: RouteNode

    var id: Int { steps.lowerBound }
    var instructionText: String {
        category == .stairs ? "계단으로 이동" : "엘리베이터로 이동"
    }
    var buttonTitle: String {
        switch category {
        case .stairs: "계단으로 층 이동 시 눌러주세요"
        default: "엘리베이터로 층 이동 시 눌러주세요"
        }
    }

    static func next(in plan: GuidanceEngine, after progress: RouteGuidanceProgress?) -> Self? {
        let order = progress.map { Double($0.stepIndex) + $0.fraction } ?? 0
        var index = 0
        while index < plan.steps.count {
            let first = plan.steps[index]
            guard first.changesFloor, first.category == .elevator || first.category == .stairs else {
                index += 1
                continue
            }
            let start = index
            while index + 1 < plan.steps.count {
                let current = plan.steps[index], next = plan.steps[index + 1]
                guard next.changesFloor, next.category == first.category, current.to.id == next.from.id,
                      (next.to.level > next.from.level) == (first.to.level > first.from.level) else { break }
                index += 1
            }
            let end = index + 1
            if Double(end) > order + 0.000_001 {
                return .init(steps: start..<end, category: first.category, from: first.from, to: plan.steps[index].to)
            }
            index = end
        }
        return nil
    }

    /// 뒤늦게 들어온 이전 층의 위치가 수동으로 확인한 진행을 되돌리지 않게 한다.
    func isReached(by progress: RouteGuidanceProgress?) -> Bool {
        guard let progress else { return false }
        return Double(progress.stepIndex) + progress.fraction >= Double(steps.upperBound) - 0.000_001
    }

    /// 안내 표시용 진행이다. 센서 위치를 생성하거나 도착을 자동 판정하는 데 사용하지 않는다.
    func displayedProgress(in plan: GuidanceEngine, liveProgress: RouteGuidanceProgress?) -> RouteGuidanceProgress? {
        if isReached(by: liveProgress) { return liveProgress }
        guard steps.lowerBound >= 0, steps.upperBound <= plan.steps.count,
              let last = plan.steps[steps].last, last.to == to else { return nil }
        let nextIndex = steps.upperBound
        guard plan.steps.indices.contains(nextIndex) else {
            return .init(stepIndex: nextIndex - 1, fraction: 1,
                         distanceAlongRoute: last.startDistance + (last.meters ?? 0), coordinate: to.coordinate,
                         maneuver: .nearDestination, distanceToManeuver: 0, remainingMeters: 0)
        }
        let next = plan.steps[nextIndex]
        let remaining = Self.distance(in: plan.steps[nextIndex...])
        let instruction = plan.instructions.first { $0.stepIndex >= nextIndex }
        let distance: Double?
        if let instruction {
            let before = plan.steps[nextIndex..<instruction.stepIndex]
            distance = before.contains(where: \.changesFloor) ? nil : Self.distance(in: before)
        } else {
            distance = remaining
        }
        return .init(stepIndex: nextIndex, fraction: 0, distanceAlongRoute: next.startDistance,
                     coordinate: next.coordinates.first ?? next.from.coordinate,
                     maneuver: instruction?.maneuver ?? .straight, distanceToManeuver: distance,
                     remainingMeters: remaining)
    }

    private static func distance(in steps: ArraySlice<GuidanceEngine.Step>) -> Double? {
        steps.reduce(Optional(0.0)) { sum, step in
            guard let sum, let meters = step.meters else { return nil }
            return sum + meters
        }
    }
}
