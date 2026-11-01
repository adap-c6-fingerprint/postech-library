import Foundation
import Testing
@testable import fingerprint_library

@MainActor
struct BookNavigationCameraTrackingTests {
    private typealias F = NavigationGuidanceTestFixture

    private func straightPlan() throws -> RouteGuidancePlan {
        let points = [0.0, 20, 40, 60].map { F.position(x: $0).coordinate }
        let value = F.make(nodes: [IndoorRoutingTestFactory.node("a"),
                                  IndoorRoutingTestFactory.node("b", x: 60)], shapes: [points])
        return try RouteGuidancePlan(route: value.route, graph: value.graph)
    }

    @Test("긴 통로는 앞쪽 30m로 제한하고 가까워지면 목적지까지 표시한다")
    func trimsTravelledPath() throws {
        let plan = try straightPlan()
        var tracking = BookNavigationCameraTracking()
        var previousSpan = Double.infinity
        for x in [0.0, 25, 45, 58, 60] {
            let position = F.position(x: x)
            let progress = try plan.progress(for: position, at: F.now)
            let next = tracking.focus(position: position, progress: progress,
                                      plan: plan, floorID: plan.destination.floorID)
            let focus = try #require(next)
            #expect(focus.coordinates.contains(position.coordinate))
            if progress.remainingMeters! <= BookNavigationCameraTracking.maximumLookAheadMeters {
                #expect(focus.coordinates.contains(plan.destination.coordinate))
            } else {
                #expect(!focus.coordinates.contains(plan.destination.coordinate))
            }
            let visiblePath = Array(focus.coordinates.dropFirst())
            #expect(RoutingGeometry.polylineLengthMeters(visiblePath) <= 30.01)
            let span = RoutingGeometry.distanceMeters(from: focus.coordinates[0], to: plan.destination.coordinate)
            #expect(span < previousSpan)
            previousSpan = span
            if x > 20 { #expect(!focus.coordinates.contains(F.position(x: 20).coordinate)) }
            if x > 40 { #expect(!focus.coordinates.contains(F.position(x: 40).coordinate)) }
            #expect(focus.minimumSpanMeters >= 12)
        }
    }

    @Test("2m보다 적게 이동했어도 안내 구간이 바뀌면 즉시 새 구간에 맞춘다")
    func updatesAtStepBoundary() throws {
        let value = F.make()
        let plan = try RouteGuidancePlan(route: value.route, graph: value.graph)
        var tracking = BookNavigationCameraTracking()
        let before = F.position(x: 19.9)
        #expect(tracking.focus(position: before, progress: try plan.progress(for: before, at: F.now),
                               plan: plan, floorID: plan.destination.floorID) != nil)
        let after = F.position(x: 20, y: 0.1)
        #expect(tracking.focus(position: after, progress: try plan.progress(for: after, at: F.now),
                               plan: plan, floorID: plan.destination.floorID) != nil)
    }

    @Test("작은 전후 흔들림을 무시하고 충분히 이동하거나 멀어지면 다시 맞춘다")
    func suppressesJitter() throws {
        let plan = try straightPlan()
        var tracking = BookNavigationCameraTracking()
        func focus(_ x: Double, force: Bool = false) throws -> BookNavigationCameraFocus? {
            let position = F.position(x: x)
            return tracking.focus(position: position, progress: try plan.progress(for: position, at: F.now),
                                  plan: plan, floorID: plan.destination.floorID, force: force)
        }
        #expect(try focus(30) != nil)
        #expect(try focus(30.5) == nil)
        #expect(try focus(29.5) == nil)
        #expect(try focus(32.5) != nil)
        #expect(try focus(30) == nil)
        #expect(try focus(27) != nil)
        #expect(try focus(27, force: true) != nil)
    }

    @Test("회전 전에는 남은 굽은 경로를 포함하고 회전 뒤에는 지난 통로를 제외한다")
    func preservesUpcomingTurn() throws {
        let value = F.make()
        let plan = try RouteGuidancePlan(route: value.route, graph: value.graph)
        var tracking = BookNavigationCameraTracking()
        let before = F.position(x: 10)
        let beforeFocus = tracking.focus(position: before,
            progress: try plan.progress(for: before, at: F.now), plan: plan, floorID: plan.destination.floorID)
        let a = try #require(beforeFocus)
        #expect(a.coordinates.contains(F.position(x: 20).coordinate))
        let after = F.position(x: 20, y: 10)
        let afterFocus = tracking.focus(position: after,
            progress: try plan.progress(for: after, at: F.now), plan: plan, floorID: plan.destination.floorID)
        let b = try #require(afterFocus)
        #expect(!b.coordinates.contains(F.position(x: 20).coordinate))
        #expect(b.coordinates.contains(plan.destination.coordinate))
    }

    @Test("층 이동이 남아 있으면 같은 층의 가까운 목적지처럼 확대하지 않는다")
    func waitsForFinalFloor() throws {
        let nodes = [IndoorRoutingTestFactory.node("a"),
                     IndoorRoutingTestFactory.node("b", x: 10, level: 1),
                     IndoorRoutingTestFactory.node("c", x: 2)]
        let value = F.make(nodes: nodes, categories: [.stairs, .stairs])
        let plan = try RouteGuidancePlan(route: value.route, graph: value.graph)
        let position = F.position(x: 0)
        var tracking = BookNavigationCameraTracking()
        #expect(tracking.focus(position: position, progress: try plan.progress(for: position, at: F.now),
                               plan: plan, floorID: plan.destination.floorID) == nil)
    }

    @Test("위치 오차가 커지면 멈춰 있어도 범위를 넓히고 작은 오차 변동으로 반복 확대하지 않는다")
    func allowsForAccuracy() throws {
        let plan = try straightPlan()
        var tracking = BookNavigationCameraTracking()
        let position = F.position(x: 58)
        let progress = try plan.progress(for: position, at: F.now)
        let narrowFocus = tracking.focus(position: position, progress: progress, plan: plan,
                                        floorID: plan.destination.floorID)
        let narrow = try #require(narrowFocus)
        let uncertain = F.position(x: 58, accuracy: 10)
        let widerFocus = tracking.focus(position: uncertain, progress: progress, plan: plan,
                                       floorID: plan.destination.floorID)
        let wider = try #require(widerFocus)
        #expect(wider.minimumSpanMeters > narrow.minimumSpanMeters)
        #expect(tracking.focus(position: position, progress: progress, plan: plan,
                               floorID: plan.destination.floorID) == nil)
        #expect(tracking.focus(position: F.position(x: 58, accuracy: 11), progress: progress, plan: plan,
                               floorID: plan.destination.floorID) == nil)
        #expect(tracking.focus(position: F.position(x: 58, level: 1), progress: progress, plan: plan,
                               floorID: plan.destination.floorID) == nil)
    }

    @Test("잘못된 남은 거리는 카메라 요청으로 만들지 않는다", arguments: [Double.nan, .infinity, -1])
    func rejectsInvalidDistance(remaining: Double) throws {
        let plan = try straightPlan()
        let position = F.position(x: 30)
        let valid = try plan.progress(for: position, at: F.now)
        let invalid = RouteGuidanceProgress(stepIndex: valid.stepIndex, fraction: valid.fraction,
            distanceAlongRoute: valid.distanceAlongRoute, coordinate: valid.coordinate,
            maneuver: valid.maneuver, distanceToManeuver: valid.distanceToManeuver, remainingMeters: remaining)
        var tracking = BookNavigationCameraTracking()
        #expect(tracking.focus(position: position, progress: invalid, plan: plan,
                               floorID: plan.destination.floorID) == nil)
    }
}
