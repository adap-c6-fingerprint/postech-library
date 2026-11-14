import Foundation
import Testing
@testable import fingerprint_library

struct FloorScenario: Sendable, CustomTestStringConvertible {
    let name: String
    var seconds = 240
    var level: @Sendable (Int) -> Int? = { _ in 2 }
    var height: (@Sendable (Double) -> Double)? = { _ in 2 * 4.26 }
    var trust: @Sendable (Int) -> Double = { _ in 1 }
    var isGap: @Sendable (Int) -> Bool = { _ in false }
    var restarts: Set<Int> = [0]
    var expected: [(Int?, Int)]
    var tolerance = 0
    var testDescription: String { name }

    static func date(_ seconds: Double) -> Date { Date(timeIntervalSinceReferenceDate: seconds) }

    static func ramp(_ points: [(Double, Double)]) -> @Sendable (Double) -> Double {
        { time in
            guard let first = points.first, time > first.0 else { return (points.first?.1 ?? 0) * 4.26 }
            for (a, b) in zip(points, points.dropFirst()) where time <= b.0 {
                return (a.1 + (b.1 - a.1) * (time - a.0) / (b.0 - a.0)) * 4.26
            }
            return (points.last?.1 ?? 0) * 4.26
        }
    }

    static var scenarios: [Self] {
        let down = ramp([(100, 3), (114, 2)])
        return [
            Self(name: "S1", seconds: 600, level: { k in
                if (150..<190).contains(k) || (300..<400).contains(k) || (k >= 430 && (k / 10) % 2 == 1) { return 3 }
                return (220..<280).contains(k) ? 1 : 2
            }, trust: { $0 < 120 ? 1 : 0.1 }, expected: [(2, 600)]),
            Self(name: "S2", seconds: 400, level: { k in
                if k < 20 || (100..<130).contains(k) { return 3 }
                return (200..<260).contains(k) ? 1 : 2
            }, trust: { _ in 0.1 }, expected: [(3, 21), (2, 379)], tolerance: 1),
            Self(name: "S3", seconds: 400, level: { (200..<260).contains($0) ? 3 : 2 }, expected: [(2, 400)]),
            Self(name: "S3b", seconds: 600, level: { (200..<350).contains($0) ? 3 : 2 },
                 expected: [(2, 293), (3, 130), (2, 177)], tolerance: 1),
            Self(name: "S4", seconds: 120, level: { $0 < 19 ? 0 : 2 }, expected: [(0, 21), (2, 99)], tolerance: 1),
            Self(name: "S5", level: { $0 < 60 ? 0 : 2 }, expected: [(0, 103), (2, 137)], tolerance: 1),
            Self(name: "S6", level: { $0 < 134 ? 3 : 2 }, height: down, expected: [(3, 111), (2, 129)]),
            Self(name: "S7", level: { $0 < 114 ? 3 : ($0 < 134 ? 4 : 2) }, height: down,
                 trust: { $0 < 100 ? 1 : 0.1 }, expected: [(3, 111), (2, 129)]),
            Self(name: "S8", level: { $0 < 114 ? 4 : ($0 < 134 ? 1 : 3) }, height: ramp([(100, 4), (114, 3)]),
                 expected: [(4, 111), (3, 129)]),
            Self(name: "S9", level: { $0 < 139 ? 0 : 4 }, height: ramp([(100, 0), (120, 4)]),
                 expected: [(0, 105), (1, 5), (2, 5), (3, 5), (4, 120)]),
            Self(name: "S10", level: { $0 < 133 ? 2 : 3 }, height: ramp([(100, 2), (114, 3)]),
                 expected: [(2, 111), (3, 129)]),
            Self(name: "S11", seconds: 260, level: { $0 < 144 ? 3 : 2 }, height: ramp([(100, 3), (125, 2)]),
                 expected: [(3, 118), (2, 142)]),
            Self(name: "S12", seconds: 300, level: { $0 < 190 ? 3 : 2 },
                 height: ramp([(100, 3), (107, 2.5), (167, 2.5), (174, 2)]), expected: [(3, 173), (2, 127)]),
            Self(name: "S13", seconds: 80, level: { (50..<65).contains($0) ? nil : 2 }, expected: [(2, 80)]),
            Self(name: "S13b", seconds: 260, level: { (50..<200).contains($0) ? nil : 2 },
                 expected: [(2, 170), (nil, 30), (2, 60)], tolerance: 1),
            Self(name: "S14", level: { $0 < 134 ? 3 : 2 }, height: nil, expected: [(3, 136), (2, 104)]),
            Self(name: "S14b", seconds: 80, level: { (50..<65).contains($0) ? nil : 2 }, height: nil,
                 expected: [(2, 60), (nil, 5), (2, 15)], tolerance: 1),
            Self(name: "S15", seconds: 1_800, level: { (1000..<1019).contains($0) ? 3 : 2 },
                 height: { 2 * 4.26 + 10 * $0 / 3_600 }, expected: [(2, 1_800)]),
            Self(name: "S16", level: { (100..<119).contains($0) ? 3 : 2 }, isGap: { (90..<100).contains($0) },
                 restarts: [0, 100], expected: [(2, 240)]),
            Self(name: "S17", seconds: 300, level: { $0 < 134 ? 3 : ($0 < 200 && ($0 / 10) % 2 == 1 ? 1 : 2) },
                 height: down, trust: { _ in 0.1 }, expected: [(3, 111), (2, 189)]),
            Self(name: "S18", seconds: 300, level: { $0 < 179 ? 2 : 1 }, height: ramp([(110, 2), (124, 1)]),
                 isGap: { (100..<160).contains($0) }, restarts: [0, 160], expected: [(2, 161), (1, 139)]),
            Self(name: "S19", seconds: 500, height: { 2 * 4.26 + ($0 >= 200 ? 3 : 0) },
                 expected: [(2, 202), (3, 133), (2, 165)]),
            Self(name: "S19b", seconds: 400, height: { 2 * 4.26 + ((200..<205).contains($0) ? 3 : 0) },
                 expected: [(2, 202), (3, 5), (2, 193)]),
            Self(name: "S20", seconds: 300, level: { $0 < 174 ? 3 : 2 }, height: down,
                 expected: [(3, 111), (2, 189)]),
            Self(name: "S20b", seconds: 300, level: { $0 < 174 ? 3 : 2 }, height: down,
                 trust: { $0 < 100 ? 1 : 0.1 }, expected: [(3, 111), (2, 189)]),
            Self(name: "S21", level: { $0 < 30 ? 0 : 2 }, trust: { _ in 0.1 },
                 expected: [(0, 41), (2, 199)], tolerance: 1),
        ]
    }

    static func named(_ name: String) -> Self { scenarios.first { $0.name == name }! }

    struct Replay {
        var states: [FloorEstimator]
        var estimates: [FloorEstimate]
    }

    func replay(duplicates: Int = 1) -> Replay {
        var estimator = FloorEstimator()
        var states: [FloorEstimator] = []
        var estimates: [FloorEstimate] = []
        for k in 0..<seconds {
            if restarts.contains(k) { estimator.locationUpdatesDidRestart() }
            if !isGap(k) {
                if let height {
                    estimator.ingestAltitude(meters: height(Double(k) + 0.4), at: Self.date(Double(k) + 0.4))
                }
                let time = Self.date(Double(k) + 0.6)
                for _ in 0..<duplicates { estimator.ingestFloor(level: level(k), trust: trust(k), at: time) }
            }
            states.append(estimator)
            estimates.append(estimator.estimate(at: Self.date(Double(k) + 0.6)))
        }
        return Replay(states: states, estimates: estimates)
    }
}

struct FloorRun: Equatable {
    var ordinal: Int?
    var start: Int
    var end: Int

    static func runs(_ ordinals: [Int?]) -> [Self] {
        var runs: [Self] = []
        for (index, ordinal) in ordinals.enumerated() {
            if runs.last?.ordinal == ordinal, !runs.isEmpty {
                runs[runs.count - 1].end = index
            } else {
                runs.append(Self(ordinal: ordinal, start: index, end: index))
            }
        }
        return runs
    }
}
