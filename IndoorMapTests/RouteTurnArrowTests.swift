import Foundation
import Testing
@testable import fingerprint_library

struct RouteTurnArrowTests {
    @Test("좌우 회전 화살표가 실제 진입·진출 경로를 따라 배치되고 화살촉이 진출 방향을 가리킨다", arguments: [1.0, -1.0])
    func followsTurn(_ sign: Double) throws {
        let factory = IndoorRoutingTestFactory.self
        let data = NavigationGuidanceTestFixture.make(nodes: [factory.node("a"), factory.node("b", x: 20), factory.node("c", x: 20, y: 20 * sign)])
        let plan = try RouteGuidancePlan(route: data.route, graph: data.graph)
        let arrow = try #require(RouteTurnArrow.make(from: plan).first)
        let corner = data.graph.nodes[1].coordinate
        let start = try #require(arrow.coordinates.first)
        let tip = try #require(arrow.coordinates.dropLast(3).last)
        #expect(arrow.maneuver == (sign > 0 ? .left : .right))
        #expect(arrow.floorID == data.graph.nodes[1].floorID)
        #expect(start.longitude < corner.longitude)
        #expect((tip.latitude - corner.latitude) * sign > 0)
        #expect(abs(RoutingGeometry.distanceMeters(from: start, to: corner) - 2) < 0.01)
        #expect(abs(RoutingGeometry.distanceMeters(from: tip, to: corner) - 2) < 0.01)
        #expect(arrow.coordinates.contains(corner))
        let validCoordinates = arrow.coordinates.allSatisfy { $0.isValid }
        #expect(validCoordinates)
    }

    @Test("역방향 이동의 화살촉도 반대 진출 통로를 가리키며 같은 그룹 곡선에 화살표를 반복하지 않는다")
    func reverseAndCurve() throws {
        let data = NavigationGuidanceTestFixture.make(reversed: true)
        let plan = try RouteGuidancePlan(route: data.route, graph: data.graph)
        let arrow = try #require(RouteTurnArrow.make(from: plan).first)
        let tip = try #require(arrow.coordinates.dropLast(3).last)
        #expect(arrow.maneuver == .right && tip.longitude < data.graph.nodes[1].coordinate.longitude)
        let group = UUID()
        let curve = NavigationGuidanceTestFixture.make(groups: [group, group])
        #expect(RouteTurnArrow.make(from: try .init(route: curve.route, graph: curve.graph)).isEmpty)
    }

    @Test("마커 방향은 현재 경로의 접선 방향이며 기기 heading을 추측하지 않는다")
    func pathBearing() throws {
        let data = NavigationGuidanceTestFixture.make()
        let plan = try RouteGuidancePlan(route: data.route, graph: data.graph)
        let east = try plan.progress(for: NavigationGuidanceTestFixture.position(x: 5), at: NavigationGuidanceTestFixture.now)
        let north = try plan.progress(for: NavigationGuidanceTestFixture.position(x: 20, y: 5), at: NavigationGuidanceTestFixture.now)
        #expect(abs((plan.bearing(at: east) ?? 0) - .pi / 2) < 0.001)
        #expect(abs(plan.bearing(at: north) ?? .infinity) < 0.001)
    }
}
