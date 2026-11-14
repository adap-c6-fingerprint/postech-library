import Foundation
import Testing
@testable import fingerprint_library

struct FloorEstimatorTests {
    @Test(arguments: FloorScenario.scenarios)
    func 문서의_v3_시나리오를_재생한다(_ scenario: FloorScenario) {
        let actual = FloorRun.runs(scenario.replay().estimates.map(\.ordinal))
        let expected = FloorRun.runs(scenario.expected.flatMap { Array(repeating: $0.0, count: $0.1) })
        #expect(actual.map(\.ordinal) == expected.map(\.ordinal))
        #expect(actual.last?.end == scenario.seconds - 1)
        for (result, reference) in zip(actual, expected) {
            #expect(abs(result.start - reference.start) <= scenario.tolerance)
            #expect(abs(result.end - reference.end) <= scenario.tolerance)
        }
    }

    @Test func 처음에는_더_많은_표를_따르고_한번_확정되면_보호한다() {
        let replay = FloorScenario.named("S4").replay()
        for second in 0..<31 { #expect(!replay.states[second].hasConfirmedFloor) }
        for second in 33..<120 { #expect(replay.states[second].hasConfirmedFloor) }
        #expect(replay.estimates[30].basis == .unconfirmed)
        #expect(replay.estimates[33].basis == .measured)
        #expect(FloorScenario.named("S16").replay().states[100].hasConfirmedFloor)
    }

    @Test func 누락_유지_한도를_넘기면_최초_확정_기록도_초기화한다() {
        let replay = FloorScenario.named("S13b").replay()
        #expect(replay.states[29].hasConfirmedFloor)
        #expect(replay.states[169].hasConfirmedFloor)
        #expect(!replay.states[170].hasConfirmedFloor)
        #expect(replay.estimates[170] == FloorEstimate(ordinal: nil, basis: .unknown))
        #expect(!replay.states[200].hasConfirmedFloor)
        #expect(replay.states[211].hasConfirmedFloor)
    }

    @Test func 층_이동량과_출력_근거를_확인한다() {
        let replay = FloorScenario.named("S6").replay()
        #expect(replay.states[115].floorOffset == -1)
        #expect(replay.states[115].baseFloor == 3)
        #expect(replay.estimates[115] == FloorEstimate(ordinal: 2, basis: .corrected))
        #expect(replay.estimates[140] == FloorEstimate(ordinal: 2, basis: .measured))
        for estimate in FloorScenario.named("S13").replay().estimates[50..<65] { #expect(estimate.basis == .held) }
        #expect(FloorScenario.named("S14").replay().estimates.allSatisfy { $0.basis == .unconfirmed })
        #expect(FloorScenario.named("S21").replay().estimates[145].basis == .unconfirmed)
    }

    @Test func 같은_위치를_반복해도_투표와_출력은_같다() {
        let scenario = FloorScenario.named("S2")
        #expect(scenario.replay().states == scenario.replay(duplicates: 5).states)
    }

    @Test func 유효하지_않거나_너무_잦거나_역순인_센서_입력은_무시한다() {
        var estimator = FloorEstimator()
        estimator.ingestAltitude(meters: 10, at: FloorScenario.date(10))
        estimator.ingestFloor(level: 2, at: FloorScenario.date(10.6))
        let original = estimator
        for altitude in [Double.nan, .infinity, -.infinity] {
            estimator.ingestAltitude(meters: altitude, at: FloorScenario.date(11))
        }
        estimator.ingestAltitude(meters: 30, at: FloorScenario.date(10.5))
        estimator.ingestAltitude(meters: 30, at: FloorScenario.date(9))
        estimator.ingestFloor(level: 4, at: FloorScenario.date(10.6))
        estimator.ingestFloor(level: 4, at: FloorScenario.date(9))
        #expect(estimator == original)
    }

    @Test func 기압_단위를_kPa로_변환하고_잘못된_기압은_거부한다() {
        #expect(FloorEstimator.altitudeMeters(fromKilopascals: 101.325) == 0)
        for pressure in [Double.nan, .infinity, 0, -1] {
            #expect(FloorEstimator.altitudeMeters(fromKilopascals: pressure) == nil)
        }
    }

    @Test func 층_범위는_번들_지도의_ordinal과_같다() async throws {
        let map = try await BundledIndoorMapLoader().loadLibrary()
        #expect(Set(map.floors.map(\.ordinal)) == Set(FloorEstimator.Configuration().validOrdinals))
    }

    @Test func 기압계가_없으면_중앙_공간_가중치를_사용하지_않는다() {
        var near = FloorScenario.named("S14")
        let far = near.replay().estimates
        near.trust = { _ in 0.1 }
        #expect(near.replay().estimates == far)
    }
}
