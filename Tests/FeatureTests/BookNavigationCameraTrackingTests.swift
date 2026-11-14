import Foundation
import Testing
@testable import fingerprint_library

@MainActor
struct BookNavigationCameraTrackingTests {
    static let now = Date(timeIntervalSinceReferenceDate: 2_000)

    private static func makeEngine() async throws -> (GuidanceEngine, UUID) {
        let map = try await BundledIndoorMapLoader().loadLibrary()
        let labels = try await BundledShelfLabelLoader().loadLibrary(on: map)
        let floor = try #require(map.floors.first { $0.ordinal == 2 })
        let shelf = try #require(labels.first { $0.floorID == floor.id && $0.realNumber == "343" && $0.side == .a })
        let start = IndoorPosition(coordinate: .init(latitude: 36.0127633, longitude: 129.3251348), floorOrdinal: 2,
                                   horizontalAccuracy: 3, timestamp: now, source: .manual)
        let plan = try await RoutePlanningLoader().load(
            on: map, labels: labels, start: start,
            stops: [RouteCandidateStop(book: makeBook(0), holdings: [], candidateShelves: [shelf])])
        return (try GuidanceEngine(route: try #require(plan.legs.first), graph: plan.graph), floor.id)
    }

    private func progress(_ engine: GuidanceEngine, at distance: Double) throws -> RouteGuidanceProgress {
        let origin = try #require(engine.steps.first).coordinates[0]
        let point = try #require(engine.candidate(atDistance: distance, level: 2, measuredFrom: origin))
        return engine.progress(at: point)
    }

    private func position(_ coordinate: IndoorMapCoordinate, accuracy: Double) -> IndoorPosition {
        IndoorPosition(coordinate: coordinate, floorOrdinal: 2, horizontalAccuracy: accuracy,
                       timestamp: Self.now, source: .sensor)
    }

    @Test func 같은_구간에서는_2초_안에_카메라를_다시_맞추지_않는다() async throws {
        let (engine, floorID) = try await Self.makeEngine()
        var tracking = BookNavigationCameraTracking()
        // 한 구간 안에서 2.5m 움직이는 상황(카메라 재조정 기준 2m 이상)을 만든다.
        let step = try #require(engine.steps.max { ($0.meters ?? 0) < ($1.meters ?? 0) })
        try #require((step.meters ?? 0) > 3)
        let first = try progress(engine, at: step.startDistance + 0.2)
        #expect(tracking.focus(position: position(first.coordinate, accuracy: 5), progress: first, plan: engine,
                               floorID: floorID, now: Self.now) != nil)
        let moved = try progress(engine, at: step.startDistance + 2.7)
        try #require(moved.stepIndex == first.stepIndex)
        #expect(tracking.focus(position: position(moved.coordinate, accuracy: 5), progress: moved, plan: engine,
                               floorID: floorID, now: Self.now.addingTimeInterval(1)) == nil)
        #expect(tracking.focus(position: position(moved.coordinate, accuracy: 5), progress: moved, plan: engine,
                               floorID: floorID, now: Self.now.addingTimeInterval(2.5)) != nil)
        #expect(tracking.focus(position: position(moved.coordinate, accuracy: 5), progress: moved, plan: engine,
                               floorID: floorID, now: Self.now.addingTimeInterval(2.6), force: true) != nil)
    }

    @Test func 카메라는_원본_좌표가_아니라_경로_위_위치를_기준으로_잡는다() async throws {
        let (engine, floorID) = try await Self.makeEngine()
        var tracking = BookNavigationCameraTracking()
        let current = try progress(engine, at: 2)
        let raw = IndoorMapCoordinate(latitude: current.coordinate.latitude + 4 / 111_195,
                                      longitude: current.coordinate.longitude)
        let result = tracking.focus(position: position(raw, accuracy: 12), progress: current,
                                    plan: engine, floorID: floorID, uncertaintyMeters: 1.5, now: Self.now)
        let focus = try #require(result)
        #expect(focus.coordinates.first == current.coordinate)
        #expect(!focus.coordinates.contains(raw))
        // 화면 범위는 흔들리는 기기 보고 오차(12m)가 아니라 추정 불확실성(1.5m)으로 정한다: 1.5×2×2+8
        #expect(abs(focus.minimumSpanMeters - 14) < 0.001)
    }

    @Test func 쓸_수_없는_오차의_위치는_따라가지_않는다() async throws {
        let (engine, floorID) = try await Self.makeEngine()
        var tracking = BookNavigationCameraTracking()
        let current = try progress(engine, at: 2)
        #expect(tracking.focus(position: position(current.coordinate, accuracy: 16), progress: current, plan: engine,
                               floorID: floorID, now: Self.now) == nil)
    }
}
