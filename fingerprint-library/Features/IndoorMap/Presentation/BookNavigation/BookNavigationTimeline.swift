import Foundation

/// 안내 화면에 표시할 전체 방문 경로. 거리가 없는 구간을 같은 길이로 꾸미지 않는다.
struct BookNavigationTimeline: Equatable {
    enum Kind: Hashable { case walk, elevator, stairs }
    struct Label: Equatable {
        let fullText: String
        let compactText: String
        let isRequired: Bool
    }
    struct Segment: Equatable, Identifiable {
        let id: Int
        let stopIndex: Int
        let steps: Range<Int>
        let kind: Kind
        let meters: Double
        let startMeters: Double
        let fromFloorID: UUID
        let toFloorID: UUID
    }
    enum MarkerKind: Equatable { case walk, elevator, stairs, book, waypoint(Int), waypoints([Int]) }
    struct Marker: Equatable, Identifiable {
        let id: Int
        let fraction: Double
        let kind: MarkerKind
    }
    let segments: [Segment]
    let markers: [Marker]
    let totalMeters: Double
    let hasCompleteDistances: Bool

    init(plans: [RouteGuidancePlan?], bookCount: Int) {
        var segments: [Segment] = []
        var markers: [Marker] = []
        var offset = 0.0
        var complete = plans.count == bookCount && bookCount > 0
        // 먼저 실제 거리로 구간을 만들고, 전체 길이가 정해지면 정규화한다.
        var endpoints: [(Double, MarkerKind)] = []
        for (stopIndex, optionalPlan) in plans.enumerated() {
            guard let plan = optionalPlan else { complete = false; continue }
            var index = 0
            while index < plan.steps.count {
                let first = index
                let step = plan.steps[index]
                let kind: Kind = Self.kind(for: step)
                var meters = 0.0
                while index < plan.steps.count {
                    let next = plan.steps[index]
                    let nextKind: Kind = Self.kind(for: next)
                    guard nextKind == kind else { break }
                    if kind != .walk, index > first {
                        let previous = plan.steps[index - 1]
                        guard next.category == step.category, previous.to.id == next.from.id,
                              (next.to.level > next.from.level) == (step.to.level > step.from.level) else { break }
                    }
                    guard let distance = next.meters, distance.isFinite, distance >= 0 else {
                        complete = false
                        index += 1
                        continue
                    }
                    meters += distance
                    index += 1
                }
                if meters > 0 || kind != .walk {
                    segments.append(.init(id: segments.count, stopIndex: stopIndex, steps: first..<index,
                        kind: kind, meters: meters, startMeters: offset,
                        fromFloorID: step.from.floorID, toFloorID: plan.steps[index - 1].to.floorID))
                    // 책 경유지와 다음 보행 시작 아이콘이 같은 자리에 겹치지 않게 한다.
                    if first != 0 || stopIndex == 0 {
                        let marker: MarkerKind = switch kind {
                        case .walk: .walk
                        case .elevator: .elevator
                        case .stairs: .stairs
                        }
                        endpoints.append((offset, marker))
                    }
                    offset += meters
                }
            }
            if bookCount > 1, let last = endpoints.last, last.0 == offset {
                switch last.1 {
                case let .waypoint(number):
                    endpoints[endpoints.count - 1] = (offset, .waypoints([number, stopIndex + 1]))
                case let .waypoints(numbers):
                    endpoints[endpoints.count - 1] = (offset, .waypoints(numbers + [stopIndex + 1]))
                default: endpoints.append((offset, .waypoint(stopIndex + 1)))
                }
            } else {
                endpoints.append((offset, bookCount == 1 ? .book : .waypoint(stopIndex + 1)))
            }
        }
        if complete {
            markers = endpoints.enumerated().map { index, entry in
                .init(id: index, fraction: offset > 0 ? entry.0 / offset : 1, kind: entry.1)
            }
        }
        self.segments = segments
        self.markers = markers
        totalMeters = offset
        hasCompleteDistances = complete
    }

    private static func kind(for step: RouteGuidancePlan.Step) -> Kind {
        guard step.changesFloor else { return .walk }
        switch step.category {
        case .elevator, .platformLift: return .elevator
        case .stairs, .escalator: return .stairs
        case .ramp, .walkway: return .walk
        }
    }

    func fraction(for segment: Segment) -> Double {
        totalMeters > 0 ? segment.meters / totalMeters : 0
    }

    func description(for segment: Segment, floors: [IndoorMapFloor]) -> String {
        switch segment.kind {
        case .elevator, .stairs:
            let facility = segment.kind == .elevator ? "엘리베이터로" : "계단으로"
            return facility + " " + floorText(segment.toFloorID, floors: floors) + " 이동"
        case .walk:
            return walkingLabel(for: segment, floors: floors).fullText
        }
    }

    func transitionTitle(for segment: Segment, floors: [IndoorMapFloor]) -> String {
        floorText(segment.toFloorID, floors: floors) + "으로"
    }

    func approachLabel(for transition: Segment, floors: [IndoorMapFloor]) -> Label {
        let floor = floorText(transition.fromFloorID, floors: floors)
        let movement = transition.kind == .stairs ? "계단으로 이동" : "엘리베이터로 이동"
        return .init(fullText: floor + "에서 " + movement,
                     compactText: floor + "에서 이동 시작",
                     isRequired: segments.first { $0.kind == transition.kind }?.id == transition.id)
    }

    func walkingLabel(for segment: Segment, floors: [IndoorMapFloor]) -> Label {
        if let next = segments.first(where: { $0.id == segment.id + 1 && $0.stopIndex == segment.stopIndex }),
           next.kind != .walk {
            return approachLabel(for: next, floors: floors)
        }
        if segment.stopIndex == 0, segment.id == segments.first?.id,
           segment.fromFloorID == segment.toFloorID {
            let title = floorText(segment.fromFloorID, floors: floors) + "에서 이동 시작"
            return .init(fullText: title, compactText: title, isRequired: false)
        }
        let followsTransition = segments.contains {
            $0.stopIndex == segment.stopIndex && $0.id < segment.id && $0.kind != .walk
        }
        if segment.stopIndex > 0, !followsTransition {
            return .init(fullText: "다음 서가로 이동", compactText: "다음 서가로 이동", isRequired: false)
        }
        return .init(fullText: floorText(segment.toFloorID, floors: floors) + "에서 서가로 이동",
                     compactText: "서가로 이동", isRequired: false)
    }

    private func floorText(_ id: UUID, floors: [IndoorMapFloor]) -> String {
        guard let floor = floors.first(where: { $0.id == id }) else { return "다음 층" }
        return floor.ordinal >= 0 ? "\(floor.ordinal + 1)층" : "지하\(-floor.ordinal)층"
    }

    func completion(of segment: Segment, stopIndex: Int, progress: RouteGuidanceProgress?) -> Double {
        if segment.stopIndex < stopIndex { return 1 }
        guard segment.stopIndex == stopIndex, let progress else { return 0 }
        if progress.stepIndex >= segment.steps.upperBound { return 1 }
        if progress.stepIndex < segment.steps.lowerBound { return 0 }
        guard segment.meters > 0 else { return progress.fraction >= 1 ? 1 : 0 }
        // startDistance는 해당 책의 경로 기준이므로 전체 세션 앞쪽 길이를 제외한다.
        let legStart = segments.first { $0.stopIndex == stopIndex }?.startMeters ?? 0
        return min(1, max(0, (progress.distanceAlongRoute - (segment.startMeters - legStart)) / segment.meters))
    }
}
