import Foundation
import Testing
@testable import fingerprint_library

struct GuidanceTrackerTests {
    typealias R = GuidanceTestRoute

    /// 첫 통로(동 0m)를 1m/s로 북쪽으로 걷는 위치
    func walk(_ seconds: Double, east: Double = 0, accuracy: Double = 4) -> IndoorPosition {
        R.position(east: east, north: 2 + seconds, accuracy: accuracy, at: seconds)
    }

    @Test func 오차가_10에서_15m_사이를_오가도_안내를_멈추지_않는다() throws {
        var tracker = GuidanceTracker(engine: try R.makeEngine())
        let accuracies = [4.0, 9, 11, 12, 9, 13, 11, 9, 12, 14, 9, 8]
        var distances: [Double] = []
        for (second, accuracy) in accuracies.enumerated() {
            let estimate = tracker.update(position: walk(Double(second), accuracy: accuracy), at: R.time(Double(second)))
            #expect(estimate.status != .lost)
            #expect(estimate.issue == nil)
            distances.append(try #require(estimate.progress).distanceAlongRoute)
        }
        #expect(zip(distances, distances.dropFirst()).allSatisfy { $1 >= $0 - 0.3 })
    }

    @Test func 쓸_수_없는_오차가_3초_넘게_이어지면_위치를_잃고_좋은_값_2번에_회복한다() throws {
        var tracker = GuidanceTracker(engine: try R.makeEngine())
        for second in 0..<3 { _ = tracker.update(position: walk(Double(second)), at: R.time(Double(second))) }
        var status: GuidanceTracker.Status = .tracking
        for second in 3..<8 {
            status = tracker.update(position: walk(Double(second), accuracy: 20), at: R.time(Double(second))).status
        }
        #expect(status == .lost)
        let first = tracker.update(position: walk(8), at: R.time(8))
        #expect(first.status == .degraded)
        let second = tracker.update(position: walk(9), at: R.time(9))
        #expect(second.status == .tracking)
        #expect(second.progress != nil)
    }

    @Test func 위치가_옆_통로로_한_번_튀어도_지금_통로를_유지한다() throws {
        var tracker = GuidanceTracker(engine: try R.makeEngine())
        var last: RouteGuidanceProgress?
        for second in 0..<9 {
            last = tracker.update(position: walk(Double(second)), at: R.time(Double(second))).progress
        }
        let before = try #require(last).distanceAlongRoute
        let jumped = tracker.update(position: walk(9, east: 5, accuracy: 6), at: R.time(9))
        let progress = try #require(jumped.progress)
        #expect(progress.stepIndex == 0)
        #expect(abs(progress.distanceAlongRoute - before) < 3)
    }

    @Test func 한_번_뒤로_튄_위치에_진행이_크게_되돌아가지_않는다() throws {
        var tracker = GuidanceTracker(engine: try R.makeEngine())
        var last: RouteGuidanceProgress?
        for second in 0..<10 {
            last = tracker.update(position: walk(Double(second)), at: R.time(Double(second))).progress
        }
        let before = try #require(last).distanceAlongRoute
        let glitch = R.position(east: 0, north: 2 + 10 - 6, accuracy: 5, at: 10)
        let after = try #require(tracker.update(position: glitch, at: R.time(10)).progress).distanceAlongRoute
        #expect(before - after < 2)
    }

    @Test func 실제로_되돌아가면_진행도_따라간다() throws {
        var tracker = GuidanceTracker(engine: try R.makeEngine())
        for second in 0..<12 { _ = tracker.update(position: walk(Double(second)), at: R.time(Double(second))) }
        var last: RouteGuidanceProgress?
        for step in 1...6 {
            let second = 11 + Double(step)
            last = tracker.update(position: R.position(east: 0, north: 13 - Double(step), at: second),
                                  at: R.time(second)).progress
        }
        #expect(try #require(last).distanceAlongRoute < 10)
    }

    @Test func 경로에서_멀면_이탈로_알리고_층을_모르면_초기화한다() throws {
        var tracker = GuidanceTracker(engine: try R.makeEngine())
        _ = tracker.update(position: walk(0), at: R.time(0))
        #expect(tracker.update(position: R.position(east: -8, north: 3, at: 1), at: R.time(1)).issue == .offRoute)
        #expect(tracker.update(position: R.position(east: 0, north: 3, at: 2, level: nil), at: R.time(2)).issue
                == .unknownFloor)
        #expect(tracker.status == .lost)
    }

    @Test func 위치_재고정은_가까운_곳에서만_편향을_보정한다() throws {
        let measured = R.point(east: 3, north: 18)
        let actual = R.point(east: 0, north: 10)
        let anchor = try #require(PositionAnchor(actual: actual, measured: measured, floorOrdinal: 2, at: R.time(0)))
        let corrected = anchor.corrected(R.point(east: 3, north: 19))
        #expect(RoutingGeometry.distanceMeters(from: corrected, to: R.point(east: 0, north: 11)) < 0.1)
        #expect(anchor.isValid(at: R.time(30), floorOrdinal: 2, near: R.point(east: 3, north: 19)))
        #expect(!anchor.isValid(at: R.time(30), floorOrdinal: 3, near: R.point(east: 3, north: 19)))
        #expect(!anchor.isValid(at: R.time(200), floorOrdinal: 2, near: R.point(east: 3, north: 19)))
        #expect(PositionAnchor(actual: R.point(east: 0, north: 50), measured: measured, floorOrdinal: 2, at: R.time(0))
                == nil)
    }

    @Test func 진행_거리로_경로_위_점과_같은_층_범위를_구한다() throws {
        let engine = try R.makeEngine()
        let point = try #require(engine.candidate(atDistance: 23, level: 2, measuredFrom: R.point(east: 3, north: 20)))
        #expect(point.index == 1)
        #expect(RoutingGeometry.distanceMeters(from: point.coordinate, to: R.point(east: 3, north: 20)) < 0.1)
        let range = engine.walkableRange(around: point, level: 2)
        #expect(range.lowerBound == 0)
        #expect(abs(range.upperBound - 46) < 0.3)
    }
}
