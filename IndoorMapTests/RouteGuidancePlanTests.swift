import Foundation
import Testing
@testable import fingerprint_library

struct RouteGuidancePlanTests {
    private typealias F = NavigationGuidanceTestFixture
    private typealias N = IndoorRoutingTestFactory

    @Test("경로 진행에 맞춰 회전 지점까지 거리와 서가까지 남은 거리를 줄인다")
    func followsPath() throws {
        let data = F.make()
        let plan = try RouteGuidancePlan(route: data.route, graph: data.graph)
        let start = try plan.progress(for: F.position(x: 0), at: F.now)
        let next = try plan.progress(for: F.position(x: 5, seconds: 2), at: F.now.addingTimeInterval(2),
                                     previous: start, elapsed: 2)
        #expect(start.maneuver == .left && next.maneuver == .left)
        #expect(abs((start.remainingMeters ?? 0) - 40) < 0.01)
        #expect(abs((next.remainingMeters ?? 0) - 35) < 0.01)
        #expect(abs((next.distanceToManeuver ?? 0) - 15) < 0.01)
        let afterTurn = try plan.progress(for: F.position(x: 20, y: 4), at: F.now)
        #expect(afterTurn.maneuver == .straight)
        #expect(abs((afterTurn.remainingMeters ?? 0) - 16) < 0.01)
    }

    @Test("반대 방향 진입에서는 같은 노드도 반대 회전 안내를 만든다")
    func reverseDirection() throws {
        let data = F.make(reversed: true)
        let plan = try RouteGuidancePlan(route: data.route, graph: data.graph)
        let progress = try plan.progress(for: F.position(x: 20, y: 20), at: F.now)
        #expect(progress.maneuver == .right)
        #expect(abs((progress.remainingMeters ?? 0) - 40) < 0.01)
    }

    @Test("우회전·유턴을 경로 진입·진출 벡터로 구분한다")
    func turns() throws {
        let right = F.make(nodes: [N.node("a"), N.node("b", x: 20), N.node("c", x: 20, y: -20)])
        let plan = try RouteGuidancePlan(route: right.route, graph: right.graph)
        #expect(try plan.progress(for: F.position(x: 0), at: F.now).maneuver == .right)
        let turn = F.make(nodes: [N.node("a"), N.node("b", x: 20), N.node("c", x: 1, y: 1)])
        let back = try RouteGuidancePlan(route: turn.route, graph: turn.graph)
        #expect(back.instructions.first?.maneuver == .turnAround)
    }

    @Test("곡선 통로는 같은 그룹의 중간 회전을 묶고 통로 모양을 따른 거리를 쓴다")
    func curvedCorridor() throws {
        let group = UUID()
        let shape = [N.node("a").coordinate, N.node("curve", x: 10, y: -10).coordinate, N.node("b", x: 20).coordinate]
        let data = F.make(groups: [group, group], shapes: [shape])
        let plan = try RouteGuidancePlan(route: data.route, graph: data.graph)
        let result = try plan.progress(for: F.position(x: 10, y: -10), at: F.now)
        #expect(plan.instructions.isEmpty)
        #expect(result.maneuver == .straight)
        #expect(abs((result.remainingMeters ?? 0) - (sqrt(200) + 20)) < 0.02)
    }

    @Test("통로 중간에 투영한 출발점 이전 구간을 남은 거리에 다시 넣지 않는다")
    func projectedStart() throws {
        let data = F.make(projectedStart: N.node("start", x: 5).coordinate)
        let plan = try RouteGuidancePlan(route: data.route, graph: data.graph)
        let result = try plan.progress(for: F.position(x: 10), at: F.now)
        #expect(abs((result.remainingMeters ?? 0) - 30) < 0.01)
        #expect(abs((result.distanceToManeuver ?? 0) - 10) < 0.01)
    }

    @Test("역방향 보행은 진행도를 되돌리며 남은 거리가 늘어난다")
    func backtracking() throws {
        let data = F.make()
        let plan = try RouteGuidancePlan(route: data.route, graph: data.graph)
        let previous = try plan.progress(for: F.position(x: 10), at: F.now)
        let result = try plan.progress(for: F.position(x: 5, seconds: 2), at: F.now.addingTimeInterval(2),
                                      previous: previous, elapsed: 2)
        #expect((result.remainingMeters ?? 0) > (previous.remainingMeters ?? 0))
    }

    @Test("경로 밖·미확인 층·낮은 정확도·오래된 위치·수동 출발점은 실시간 안내로 쓰지 않는다")
    func rejectsUnusablePositions() throws {
        let data = F.make()
        let plan = try RouteGuidancePlan(route: data.route, graph: data.graph)
        #expect(throws: RouteGuidanceError.offRoute) { try plan.progress(for: F.position(x: 0, y: 10), at: F.now) }
        #expect(throws: RouteGuidanceError.unknownFloor) { try plan.progress(for: F.position(x: 0, level: nil), at: F.now) }
        #expect(throws: RouteGuidanceError.unknownFloor) { try plan.progress(for: F.position(x: 0, level: 99), at: F.now) }
        #expect(throws: RouteGuidanceError.inaccuratePosition) { try plan.progress(for: F.position(x: 0, accuracy: 50), at: F.now) }
        #expect(throws: RouteGuidanceError.stalePosition) { try plan.progress(for: F.position(x: 0, seconds: -11), at: F.now) }
        let manual = IndoorPosition(coordinate: N.node("a").coordinate, floorOrdinal: 0,
            horizontalAccuracy: nil, timestamp: F.now, source: .manual)
        #expect(throws: RouteGuidanceError.invalidPosition) { try plan.progress(for: manual, at: F.now) }
    }

    @Test("교차점 첫 위치는 모호함을 알리고 진행 이력이 있으면 앞선 구간에 붙인다")
    func crossing() throws {
        let data = F.make(nodes: [N.node("a", x: -10), N.node("b", x: 10),
            N.node("c", x: 10, y: 10), N.node("d", y: 10), N.node("e", y: -10)])
        let plan = try RouteGuidancePlan(route: data.route, graph: data.graph)
        #expect(throws: RouteGuidanceError.ambiguousPosition) { try plan.progress(for: F.position(x: 0), at: F.now) }
        let previous = try plan.progress(for: F.position(x: -5), at: F.now)
        let result = try plan.progress(for: F.position(x: 0, seconds: 2), at: F.now.addingTimeInterval(2),
                                      previous: previous, elapsed: 2)
        #expect(result.stepIndex == 0)
    }

    @Test("경로의 먼 뒷구간으로 갑자기 이동한 위치는 진행도를 건너뛰지 않는다")
    func rejectsJump() throws {
        let data = F.make(nodes: [N.node("a"), N.node("b", x: 100)])
        let plan = try RouteGuidancePlan(route: data.route, graph: data.graph)
        let previous = try plan.progress(for: F.position(x: 0), at: F.now)
        #expect(throws: RouteGuidanceError.ambiguousPosition) {
            try plan.progress(for: F.position(x: 80, seconds: 1), at: F.now.addingTimeInterval(1), previous: previous, elapsed: 1)
        }
    }

    @Test("층간 이동은 회전 대신 이동 수단·목표 층을 안내하고 새 층의 경로로 진행한다")
    func floorChange() throws {
        let nodes = [N.node("a"), N.node("b", x: 10), N.node("c", x: 10, level: 1), N.node("d", x: 20, level: 1)]
        let data = F.make(nodes: nodes, categories: [.walkway, .elevator, .walkway])
        let plan = try RouteGuidancePlan(route: data.route, graph: data.graph)
        let before = try plan.progress(for: F.position(x: 5), at: F.now)
        #expect(before.maneuver == .changeFloor(.elevator, to: nodes[2].floorID))
        #expect(abs((before.remainingMeters ?? 0) - 21) < 0.01)
        let after = try plan.progress(for: F.position(x: 15, level: 1), at: F.now)
        #expect(after.maneuver == .straight)
        #expect(abs((after.remainingMeters ?? 0) - 5) < 0.01)
    }

    @Test("여러 층간 간선의 개별 거리가 없으면 남은 비용을 임의로 나누지 않는다")
    func unknownTransitionCosts() throws {
        let data = F.make(nodes: [N.node("a"), N.node("b", level: 1), N.node("c", level: 2), N.node("d", x: 10, level: 2)],
                          categories: [.elevator, .elevator, .walkway])
        let plan = try RouteGuidancePlan(route: data.route, graph: data.graph)
        let before = try plan.progress(for: F.position(x: 0), at: F.now)
        #expect(before.remainingMeters == nil)
        #expect(before.maneuver == .changeFloor(.elevator, to: data.graph.nodes[2].floorID))
        let after = try plan.progress(for: F.position(x: 5, level: 2), at: F.now)
        #expect(abs((after.remainingMeters ?? 0) - 5) < 0.01)
    }

    @Test("0간선 경로에서도 실제 위치가 도착 노드 근처인 경우에만 서가 근처로 표시한다")
    func zeroLengthRoute() throws {
        let data = F.make(nodes: [N.node("a")])
        let plan = try RouteGuidancePlan(route: data.route, graph: data.graph)
        #expect(try plan.progress(for: F.position(x: 0), at: F.now).maneuver == .nearDestination)
        #expect(throws: RouteGuidanceError.offRoute) { try plan.progress(for: F.position(x: 10), at: F.now) }
    }
}
