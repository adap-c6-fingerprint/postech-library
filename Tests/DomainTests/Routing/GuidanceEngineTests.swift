import Foundation
import Testing
@testable import fingerprint_library

/// 기존 `progress(for:)` 동작을 고정한다. 후보 계산 분리 전후로 결과가 같아야 한다.
struct GuidanceEngineTests {
    typealias R = GuidanceTestRoute

    @Test func 경로_위_위치를_투영해_진행과_남은_거리를_계산한다() throws {
        let engine = try R.makeEngine()
        let progress = try engine.progress(for: R.position(east: 0.5, north: 5, at: 0), at: R.time(0))
        #expect(progress.stepIndex == 0)
        #expect(abs(progress.distanceAlongRoute - 5) < 0.2)
        #expect(abs((progress.remainingMeters ?? 0) - 41) < 0.3)
        #expect(progress.maneuver == .right)
        #expect(abs((progress.distanceToManeuver ?? 0) - 15) < 0.3)
    }

    @Test func 오차가_10m를_넘으면_부정확한_위치로_거른다() throws {
        let engine = try R.makeEngine()
        #expect(throws: RouteGuidanceError.inaccuratePosition) {
            try engine.progress(for: R.position(east: 0, north: 5, accuracy: 10.5, at: 0), at: R.time(0))
        }
    }

    @Test func 매칭_반경_밖이면_경로_이탈이다() throws {
        let engine = try R.makeEngine()
        #expect(throws: RouteGuidanceError.offRoute) {
            try engine.progress(for: R.position(east: -6, north: 5, at: 0), at: R.time(0))
        }
    }

    @Test func 층을_모르면_안내하지_않는다() throws {
        let engine = try R.makeEngine()
        #expect(throws: RouteGuidanceError.unknownFloor) {
            try engine.progress(for: R.position(east: 0, north: 5, at: 0, level: nil), at: R.time(0))
        }
    }

    @Test func 두_통로_사이에서는_첫_위치를_정하지_않는다() throws {
        let engine = try R.makeEngine()
        #expect(throws: RouteGuidanceError.ambiguousPosition) {
            try engine.progress(for: R.position(east: 3, north: 10, at: 0), at: R.time(0))
        }
    }

    @Test func 이전_진행이_있으면_가까운_순서의_후보를_고른다() throws {
        let engine = try R.makeEngine()
        let first = try engine.progress(for: R.position(east: 0.5, north: 10, at: 0), at: R.time(0))
        let next = try engine.progress(for: R.position(east: 2.9, north: 11, at: 1), at: R.time(1),
                                       previous: first, elapsed: 1)
        #expect(next.stepIndex == 0)
    }

    @Test func 목적지_근처에서는_도착_안내를_한다() throws {
        let engine = try R.makeEngine()
        let first = try engine.progress(for: R.position(east: 6, north: 3, at: 0), at: R.time(0))
        let progress = try engine.progress(for: R.position(east: 6, north: 0.5, at: 1), at: R.time(1),
                                           previous: first, elapsed: 1)
        #expect(progress.maneuver == .nearDestination)
    }
}
