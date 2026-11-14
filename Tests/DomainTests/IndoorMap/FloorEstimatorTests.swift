import Foundation
import Testing
@testable import fingerprint_library

struct FloorEstimatorTests {
    private struct Run: Equatable {
        var floor: Int?
        var count: Int
    }

    struct Scenario: Sendable, CustomTestStringConvertible {
        let name: String
        var seconds = 60
        var pressure: @Sendable (Int) -> Bool = { _ in false }
        var location: @Sendable (Int) -> Bool = { _ in true }
        var altitude: @Sendable (Double) -> Double = { _ in 9 }
        var floor: @Sendable (Int) -> Int? = { _ in 2 }
        var restarts: Set<Int> = []
        var expected: [(Int?, Int)]
        var tolerance = 0
        var testDescription: String { name }
    }

    static func pressure(meters: Double) -> Double {
        101.325 * pow(1 - (60 + meters) / 44_330.8, 1 / 0.190263)
    }

    static func date(_ seconds: Double) -> Date { Date(timeIntervalSinceReferenceDate: seconds) }

    private static func stairs(_ time: Double) -> Double {
        18 - 4.5 * min(1, max(0, (time - 25) / 10))
    }

    static var scenarios: [Scenario] {
        [
            Scenario(name: "U1: 한 번의 nil", floor: { $0 == 30 ? nil : 2 }, expected: [(2, 60)]),
            Scenario(name: "U2: 기압 없이 15초 nil", floor: { (30..<45).contains($0) ? nil : 2 },
                     expected: [(2, 40), (nil, 5), (2, 15)]),
            Scenario(name: "U3: 기압으로 15초 nil 유지", pressure: { _ in true },
                     floor: { (30..<45).contains($0) ? nil : 2 }, expected: [(2, 60)]),
            Scenario(name: "U4: 지도에 없는 층", floor: { (30..<35).contains($0) ? 7 : 2 }, expected: [(2, 60)]),
            Scenario(name: "U5: 잘못된 층 3초", seconds: 120, floor: { (60..<63).contains($0) ? 3 : 2 },
                     expected: [(2, 120)]),
            Scenario(name: "U6: 잘못된 층 5초", seconds: 120, floor: { (60..<65).contains($0) ? 3 : 2 },
                     expected: [(2, 63), (3, 4), (2, 53)]),
            Scenario(name: "U7: 기압이 있을 때 잘못된 층 19초", seconds: 400, pressure: { _ in true },
                     floor: { (300..<319).contains($0) ? 3 : 2 }, expected: [(2, 400)]),
            Scenario(name: "U8: 잘못된 층이 계속되면 재보정", seconds: 500, pressure: { _ in true },
                     floor: { (300..<360).contains($0) ? 3 : 2 }, expected: [(2, 342), (3, 33), (2, 125)], tolerance: 2),
            Scenario(name: "U9: 기압 없이 번갈아 나오는 층", seconds: 400,
                     floor: { (300..<360).contains($0) && $0.isMultiple(of: 2) ? 3 : 2 }, expected: [(2, 400)]),
            Scenario(name: "U9: 기압과 번갈아 나오는 층", seconds: 400, pressure: { _ in true },
                     floor: { (300..<360).contains($0) && $0.isMultiple(of: 2) ? 3 : 2 }, expected: [(2, 400)]),
            Scenario(name: "U10: 계단과 CLFloor 지연", seconds: 120, pressure: { _ in true }, altitude: stairs,
                     floor: { $0 < 54 ? 4 : 3 }, expected: [(4, 33), (3, 87)]),
            Scenario(name: "U10b: 기압 없는 계단", seconds: 120, altitude: stairs,
                     floor: { $0 < 54 ? 4 : 3 }, expected: [(4, 57), (3, 63)]),
            Scenario(name: "U10c: 유예 시간을 초과한 CLFloor 지연", seconds: 140, pressure: { _ in true }, altitude: stairs,
                     floor: { $0 < 85 ? 4 : 3 }, expected: [(4, 33), (3, 40), (4, 31), (3, 36)], tolerance: 2),
            Scenario(name: "U11: 네 층 엘리베이터 이동", seconds: 180, pressure: { _ in true },
                     altitude: { 18 * min(1, max(0, ($0 - 60) / 15)) }, floor: { $0 < 94 ? 0 : 4 },
                     expected: [(0, 64), (1, 4), (2, 4), (3, 4), (4, 104)]),
            Scenario(name: "U12: 일시적 기압 오차에서 복귀", seconds: 500, pressure: { _ in true },
                     altitude: { (300..<320).contains($0) ? 5.5 : 9 }, expected: [(2, 302), (1, 20), (2, 178)]),
            Scenario(name: "U13: 지속적인 기압 오차를 CLFloor로 보정", seconds: 500, pressure: { _ in true },
                     altitude: { $0 >= 300 ? 5.5 : 9 }, expected: [(2, 302), (1, 40), (2, 158)]),
            Scenario(name: "U14: 꼭대기 층에서 지도 범위를 넘지 않음", seconds: 500, pressure: { _ in true },
                     altitude: { (300..<320).contains($0) ? 21.5 : 18 }, floor: { _ in 4 }, expected: [(4, 500)]),
            Scenario(name: "U15: 시작 직후 잘못된 기준층 보정", seconds: 120, pressure: { _ in true },
                     floor: { $0 < 19 ? 0 : 2 }, expected: [(0, 22), (2, 98)], tolerance: 2),
            Scenario(name: "U15b: 기압 없이 초기 기준층 보정", seconds: 120,
                     floor: { $0 < 19 ? 0 : 2 }, expected: [(0, 21), (2, 99)], tolerance: 2),
            Scenario(name: "U16: 60초 중단 사이 두 층 이동", seconds: 260,
                     pressure: { !(100..<160).contains($0) }, location: { !(100..<160).contains($0) },
                     altitude: { $0 < 130 ? 18 : 9 }, floor: { $0 < 100 ? 4 : ($0 < 179 ? 0 : 2) },
                     restarts: [160], expected: [(4, 161), (2, 99)]),
            Scenario(name: "U17: 200초 중단은 이전 추정 만료", seconds: 400,
                     pressure: { !(100..<300).contains($0) }, location: { !(100..<300).contains($0) },
                     altitude: { $0 < 130 ? 18 : 9 }, floor: { $0 < 100 ? 4 : ($0 < 319 ? 0 : 2) },
                     restarts: [300], expected: [(4, 219), (nil, 81), (0, 22), (2, 78)], tolerance: 2),
        ]
    }

    private func replay(_ scenario: Scenario, duplicates: Int = 1) -> [FloorEstimate] {
        var estimator = FloorEstimator()
        return (0..<scenario.seconds).map { second in
            if scenario.restarts.contains(second) { estimator.locationUpdatesDidRestart() }
            let pressureTime = Double(second) + 0.4
            let positionTime = Double(second) + 0.6
            if scenario.pressure(second) {
                estimator.ingestPressure(kilopascals: Self.pressure(meters: scenario.altitude(pressureTime)),
                                         at: Self.date(pressureTime))
            }
            if scenario.location(second) {
                for _ in 0..<duplicates {
                    estimator.ingestFloor(level: scenario.floor(second), at: Self.date(positionTime))
                }
            }
            return estimator.estimate(at: Self.date(positionTime))
        }
    }

    private func runs(_ levels: [Int?]) -> [Run] {
        levels.reduce(into: []) { runs, level in
            if runs.last?.floor == level, !runs.isEmpty {
                runs[runs.count - 1].count += 1
            } else {
                runs.append(Run(floor: level, count: 1))
            }
        }
    }

    @Test(arguments: scenarios)
    func 문서의_센서_시나리오를_재생한다(_ scenario: Scenario) {
        let actual = runs(replay(scenario).map(\.ordinal))
        let expected = scenario.expected.map { Run(floor: $0.0, count: $0.1) }
        #expect(actual.map(\.floor) == expected.map(\.floor))
        #expect(actual.reduce(0) { $0 + $1.count } == scenario.seconds)
        var actualStart = 0
        var expectedStart = 0
        for (result, reference) in zip(actual, expected) {
            #expect(abs(actualStart - expectedStart) <= scenario.tolerance)
            actualStart += result.count
            expectedStart += reference.count
        }
    }

    @Test func U18_나침반이_같은_위치를_반복해도_표가_늘지_않는다() {
        let scenario = Scenario(name: "U18", seconds: 40, floor: { (20..<23).contains($0) ? 3 : 2 }, expected: [])
        #expect(replay(scenario) == replay(scenario, duplicates: 5))
    }

    @Test func 추정의_근거와_유지_만료를_구분한다() {
        var estimator = FloorEstimator()
        #expect(estimator.estimate(at: Self.date(0)) == FloorEstimate(ordinal: nil, basis: .unknown))
        estimator.ingestFloor(level: 2, at: Self.date(0))
        #expect(estimator.estimate(at: Self.date(0)) == FloorEstimate(ordinal: 2, basis: .measured))
        estimator.ingestFloor(level: nil, at: Self.date(1))
        #expect(estimator.estimate(at: Self.date(1)) == FloorEstimate(ordinal: 2, basis: .held))
        estimator.ingestFloor(level: 3, at: Self.date(2))
        #expect(estimator.estimate(at: Self.date(2)) == FloorEstimate(ordinal: 2, basis: .corrected))
        #expect(estimator.estimate(at: Self.date(13)) == FloorEstimate(ordinal: nil, basis: .unknown))
    }

    @Test func 유효하지_않거나_역순인_기압은_상태를_바꾸지_않는다() {
        var estimator = FloorEstimator()
        estimator.ingestPressure(kilopascals: Self.pressure(meters: 9), at: Self.date(1))
        let original = estimator
        for pressure in [Double.nan, .infinity, 0, -1] {
            estimator.ingestPressure(kilopascals: pressure, at: Self.date(2))
        }
        estimator.ingestPressure(kilopascals: Self.pressure(meters: 18), at: Self.date(0))
        estimator.ingestPressure(kilopascals: Self.pressure(meters: 18), at: Self.date(1.5))
        #expect(estimator == original)
    }

    @Test func 늦게_온_층_관측은_표와_만료_시각을_바꾸지_않는다() {
        var estimator = FloorEstimator()
        estimator.ingestFloor(level: 2, at: Self.date(10))
        let original = estimator
        estimator.ingestFloor(level: 4, at: Self.date(9))
        estimator.ingestFloor(level: 4, at: Self.date(10))
        #expect(estimator == original)
    }

    @Test func 층_범위는_번들_지도의_ordinal과_같다() async throws {
        let map = try await BundledIndoorMapLoader().loadLibrary()
        #expect(Set(map.floors.map(\.ordinal)) == Set(FloorEstimator.Configuration().validOrdinals))
    }

    @Test(arguments: [1, 2, 3, 4])
    func 문서의_층_관측_구간을_가상_기압과_재생한다(mode: Int) {
        // 문서에 요약된 관측 구간이다. 실제 기압 로그를 검증하는 테스트는 아니다.
        let sessions: [(truth: Int, runs: [(Int?, Int)])] = [
            (4, [(4, 6), (nil, 1), (4, 117)]),
            (3, [(1, 20), (3, 30), (nil, 1), (3, 31), (nil, 1), (3, 30), (nil, 1), (3, 87), (nil, 1), (3, 44)]),
            (2, [(3, 20), (2, 183)]), (1, [(1, 105)]),
        ]
        let gaps = [16, 15, 26]
        var floors: [Int?] = []
        var truths: [Int?] = []
        var heights: [Double] = []
        var starts: Set<Int> = []
        for (index, session) in sessions.enumerated() {
            starts.insert(floors.count)
            for (floor, count) in session.runs {
                floors += Array(repeating: floor, count: count)
                truths += Array(repeating: session.truth, count: count)
                heights += Array(repeating: Double(session.truth) * 4.5, count: count)
            }
            if index < gaps.count {
                let gap = gaps[index]
                for second in 0..<gap {
                    floors.append(nil)
                    truths.append(nil)
                    let fraction = min(1, max(0, (Double(second) + 0.4 - 2) / Double(gap - 4)))
                    heights.append((Double(session.truth) + Double(sessions[index + 1].truth - session.truth) * fraction) * 4.5)
                }
            }
        }
        #expect(floors.count == 735)
        #expect(truths.compactMap { $0 }.count == 678)
        var estimator = FloorEstimator()
        var output: [Int?] = []
        var wrongCount = 0
        for second in floors.indices {
            if (mode == 2 || mode == 4), starts.contains(second) { estimator.locationUpdatesDidRestart() }
            if mode == 3 || (mode == 4 && truths[second] != nil) {
                estimator.ingestPressure(kilopascals: Self.pressure(meters: heights[second]), at: Self.date(Double(second) + 0.4))
            }
            guard let truth = truths[second] else { continue }
            let time = Self.date(Double(second) + 0.6)
            estimator.ingestFloor(level: floors[second], at: time)
            let floor = estimator.estimate(at: time).ordinal
            output.append(floor)
            if floor != truth { wrongCount += 1 }
        }
        #expect(output.allSatisfy { $0 != nil })
        let actual = runs(output)
        switch mode {
        case 1:
            #expect(actual == [Run(floor: 4, count: 124), Run(floor: 1, count: 23), Run(floor: 3, count: 246),
                               Run(floor: 2, count: 180), Run(floor: 1, count: 105)])
            #expect(wrongCount == 46)
        case 2:
            #expect(actual.count == 5)
            #expect(wrongCount <= 46)
        case 3:
            #expect(actual == [Run(floor: 4, count: 124), Run(floor: 3, count: 246),
                               Run(floor: 2, count: 203), Run(floor: 1, count: 105)])
            #expect(wrongCount == 0)
        default:
            #expect(actual == [Run(floor: 4, count: 125), Run(floor: 3, count: 246),
                               Run(floor: 2, count: 203), Run(floor: 1, count: 104)])
            #expect(wrongCount == 3)
        }
    }
}
