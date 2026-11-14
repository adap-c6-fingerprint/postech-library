import Foundation
import Testing
@testable import fingerprint_library

struct FloorEstimatorReplayTests {
    @Test(arguments: [1, 2, 3])
    func 문서에_요약된_관측_구간을_가상_기압과_재생한다(mode: Int) {
        // (정답, [(CLFloor 값, 신뢰도, 초)]). 세션 순서는 5층, 4층, 3층, 2층이다.
        let sessions: [(truth: Int, runs: [(level: Int?, trust: Double, seconds: Int)])] = [
            (4, [(4, 1, 6), (nil, 1, 1), (4, 1, 18), (4, 0.1, 8), (4, 1, 89), (4, 0.1, 2)]),
            (3, [(1, 0.1, 20), (3, 0.1, 22), (3, 1, 8), (nil, 1, 1), (3, 1, 31), (nil, 1, 1), (3, 1, 30),
                 (nil, 1, 1), (3, 1, 49), (3, 0.1, 9), (3, 1, 29), (nil, 1, 1), (3, 1, 43), (3, 0.1, 1)]),
            (2, [(3, 0.1, 20), (2, 0.1, 6), (2, 1, 22), (2, 0.1, 8), (2, 1, 1), (2, 0.1, 3), (2, 1, 2), (2, 0.1, 1),
                 (2, 1, 140)]),
            (1, [(1, 0.1, 2), (1, 1, 1), (1, 0.1, 6), (1, 1, 2), (1, 0.1, 5), (1, 1, 3), (1, 0.1, 14), (1, 1, 3),
                 (1, 0.1, 23), (1, 1, 46)]),
        ]
        let gapSeconds = [16, 15, 26]   // 세션 사이에 위치가 없는 초
        var floors: [Int?] = []
        var trusts: [Double] = []
        var truths: [Int?] = []
        var heights: [Double] = []
        var starts: Set<Int> = []
        for (index, session) in sessions.enumerated() {
            starts.insert(floors.count)
            for (floor, trust, count) in session.runs {
                floors += Array(repeating: floor, count: count)
                trusts += Array(repeating: trust, count: count)
                truths += Array(repeating: session.truth, count: count)
                heights += Array(repeating: Double(session.truth) * 4.26, count: count)
            }
            if index < gapSeconds.count {
                let gap = gapSeconds[index]
                for second in 0..<gap {
                    floors.append(nil)
                    trusts.append(1)
                    truths.append(nil)
                    let fraction = min(1, max(0, (Double(second) + 0.4 - 2) / Double(gap - 4)))
                    heights.append((Double(session.truth) + Double(sessions[index + 1].truth - session.truth) * fraction) * 4.26)
                }
            }
        }
        #expect(floors.count == 735)
        #expect(truths.compactMap { $0 }.count == 678)
        var estimator = FloorEstimator()
        var output: [Int?] = []
        var wrong = 0
        for second in floors.indices {
            if starts.contains(second) { estimator.locationUpdatesDidRestart() }
            if mode == 1 || (mode == 2 && truths[second] != nil) {
                estimator.ingestAltitude(meters: heights[second], at: FloorScenario.date(Double(second) + 0.4))
            }
            guard let truth = truths[second] else { continue }
            let time = FloorScenario.date(Double(second) + 0.6)
            estimator.ingestFloor(level: floors[second], trust: trusts[second], at: time)
            let floor = estimator.estimate(at: time).ordinal
            output.append(floor)
            if floor != truth { wrong += 1 }
        }
        let expected: [(Int?, Int)] = switch mode {
        case 1: [(4, 124), (3, 246), (2, 203), (1, 105)]
        case 2: [(4, 125), (3, 246), (2, 203), (1, 104)]
        default: [(4, 124), (1, 21), (3, 246), (2, 182), (1, 105)]
        }
        let actualRuns = FloorRun.runs(output)
        let expectedRuns = FloorRun.runs(expected.flatMap { Array(repeating: $0.0, count: $0.1) })
        #expect(actualRuns.map(\.ordinal) == expectedRuns.map(\.ordinal))
        #expect(output.allSatisfy { $0 != nil })
        for (actual, expected) in zip(actualRuns, expectedRuns) {
            #expect(abs(actual.start - expected.start) <= (mode == 3 ? 1 : 0))
            #expect(abs(actual.end - expected.end) <= (mode == 3 ? 1 : 0))
        }
        if mode == 1 { #expect(wrong == 0) }
        if mode == 2 { #expect(wrong == 3) }
        if mode == 3 { #expect(abs(wrong - 42) <= 2) }
    }
}
