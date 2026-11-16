import Foundation
import Testing
@testable import fingerprint_library

/// 도서관 현장 측정 기록을 그대로 재생해 기존 판정과 `GuidanceTracker`를 같은 지표로 비교한다.
/// 기록에는 실내 이동 좌표가 들어 있어 저장소에 넣지 않는다. 기록 폴더가 있을 때만 실행한다.
///
/// 실행: `TEST_RUNNER_GUIDANCE_REPLAY_DIR=<세션 폴더들이 있는 경로> xcodebuild test ...`
/// 각 세션 폴더에는 실험 브랜치 진단 기록의 `session.jsonl`이 있어야 한다.
/// 층 판정은 이 비교 대상이 아니므로, 재생 구간은 목적지 층 한 층으로 고정한다.
@MainActor
struct GuidanceReplayTests {
    nonisolated static let directory = ProcessInfo.processInfo.environment["GUIDANCE_REPLAY_DIR"]
    nonisolated static let sessions = ["1차 측정", "4차 측정"]

    @Test(.enabled(if: directory != nil), arguments: sessions)
    func 재생하면_새_추정이_기존보다_덜_멈추고_덜_튄다(session: String) async throws {
        let folder = URL(filePath: try #require(Self.directory)).appending(path: session)
        let replay = try ReplaySession(folder: folder)
        let engine = try await replay.makeEngine()

        let before = ReplayMetrics(replay.runLegacy(engine: engine))
        let after = ReplayMetrics(replay.runTracker(engine: engine))
        print("[replay] \(session) samples=\(replay.samples.count)")
        print("[replay] \(session) before \(before.summary)")
        print("[replay] \(session) after  \(after.summary)")
        if ProcessInfo.processInfo.environment["GUIDANCE_REPLAY_TRACE"] != nil {
            let legacy = replay.runLegacy(engine: engine), tracked = replay.runTracker(engine: engine)
            let t0 = replay.samples[0].time
            for (index, sample) in replay.samples.enumerated() {
                func text(_ p: RouteGuidanceProgress?) -> String {
                    p.map { String(format: "%5.1f %@", $0.distanceAlongRoute, "\($0.maneuver)") } ?? "  -  "
                }
                print(String(format: "[trace] %5.1f acc=%4.1f ", sample.time.timeIntervalSince(t0),
                             sample.position.horizontalAccuracy ?? -1)
                      + "old=\(text(legacy[index].progress)) new=\(text(tracked[index].progress))")
            }
        }

        #expect(after.hiddenRatio < before.hiddenRatio)
        #expect(after.visibilityToggles <= before.visibilityToggles)
        #expect(after.jumps <= before.jumps)
        // 기존 판정은 불확실한 구간을 숨겨서 역행이 적게 잡힌다. 숨기지 않는 대신 작은 보정(합계 2m)까지는 허용한다.
        #expect(after.regressionMeters <= max(before.regressionMeters, 2))
        #expect(after.maneuverFlips <= before.maneuverFlips)
    }
}

// MARK: - 기록 읽기

@MainActor
struct ReplaySession {
    struct Sample {
        let time: Date
        let position: IndoorPosition
    }

    let samples: [Sample]
    let destination: IndoorMapCoordinate
    let floorOrdinal: Int

    init(folder: URL) throws {
        let text = try String(contentsOf: folder.appending(path: "session.jsonl"), encoding: .utf8)
        let lines = text.split(separator: "\n").compactMap {
            try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any]
        }
        func date(_ value: Any?) -> Date? {
            (value as? String).flatMap { try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse($0) }
        }
        let routes = lines.filter { $0["type"] as? String == "route" }
        guard let route = routes.last,
              let latitude = route["destinationLatitude"] as? Double,
              let longitude = route["destinationLongitude"] as? Double,
              let floor = route["destinationFloorOrdinal"] as? Int else { throw ReplayError.missingRoute }
        destination = .init(latitude: latitude, longitude: longitude)
        floorOrdinal = floor
        // 재탐색 이후, 또는 층 이동을 확인한 이후의 목적지 층 구간만 재생한다.
        let segmentStart = ([date(route["at"])] + lines
            .filter { $0["type"] as? String == "event" && $0["name"] as? String == "floor_transition_confirmed" }
            .map { date($0["at"]) })
            .compactMap { $0 }.max() ?? .distantPast
        samples = lines.compactMap { line -> Sample? in
            guard line["type"] as? String == "location",
                  let time = date(line["timestamp"]), time >= segmentStart,
                  let latitude = line["latitude"] as? Double, let longitude = line["longitude"] as? Double,
                  let accuracy = line["horizontalAccuracy"] as? Double else { return nil }
            return .init(time: time, position: .init(
                coordinate: .init(latitude: latitude, longitude: longitude), floorOrdinal: floor,
                horizontalAccuracy: accuracy, timestamp: time, source: .sensor))
        }
        guard samples.count >= 10 else { throw ReplayError.tooFewSamples }
    }

    func makeEngine() async throws -> GuidanceEngine {
        let map = try await BundledIndoorMapLoader().loadLibrary()
        let labels = try await BundledShelfLabelLoader().loadLibrary(on: map)
        let floor = try #require(map.floors.first { $0.ordinal == floorOrdinal })
        let shelf = try #require(labels.filter { $0.floorID == floor.id }.min {
            RoutingGeometry.distanceMeters(from: $0.geometry.center, to: destination)
                < RoutingGeometry.distanceMeters(from: $1.geometry.center, to: destination)
        })
        let first = try #require(samples.first).position
        let start = IndoorPosition(coordinate: first.coordinate, floorOrdinal: floorOrdinal, horizontalAccuracy: 0,
                                   timestamp: first.timestamp, source: .manual)
        let plan = try await RoutePlanningLoader().load(
            on: map, labels: labels, start: start,
            stops: [RouteCandidateStop(book: makeBook(1), holdings: [], candidateShelves: [shelf])])
        let leg = try #require(plan.legs.first)
        let engine = try GuidanceEngine(route: leg, graph: plan.graph)
        #expect(RoutingGeometry.distanceMeters(from: engine.destination.coordinate, to: destination) < 5)
        return engine
    }

    /// 지금 앱의 판정: 오차 10m 초과면 숨기고, 실패하면 진행을 비운다.
    func runLegacy(engine: GuidanceEngine) -> [ReplayFrame] {
        var previous: RouteGuidanceProgress?
        var previousTime: Date?
        return samples.map { sample in
            let accuracy = sample.position.horizontalAccuracy ?? .infinity
            guard accuracy <= GuidanceEngine.maximumAccuracyMeters,
                  let progress = try? engine.progress(for: sample.position, at: sample.time, previous: previous,
                      elapsed: previousTime.map { sample.time.timeIntervalSince($0) }) else {
                previous = nil
                previousTime = nil
                return .init(time: sample.time, progress: nil)
            }
            previous = progress
            previousTime = sample.time
            return .init(time: sample.time, progress: progress)
        }
    }

    func runTracker(engine: GuidanceEngine) -> [ReplayFrame] {
        var tracker = GuidanceTracker(engine: engine)
        return samples.map { sample in
            let estimate = tracker.update(position: sample.position, at: sample.time)
            let visible = estimate.issue == nil && estimate.status != .lost
            return .init(time: sample.time, progress: visible ? estimate.progress : nil)
        }
    }
}

enum ReplayError: Error { case missingRoute, tooFewSamples }

struct ReplayFrame {
    let time: Date
    let progress: RouteGuidanceProgress?
}

/// 진단 기록 요약과 같은 기준의 안내 안정성 지표
struct ReplayMetrics {
    let hiddenRatio: Double
    let visibilityToggles: Int
    /// 1초 사이 진행 거리가 3m 넘게 바뀐 횟수
    let jumps: Int
    let regressionCount: Int
    let regressionMeters: Double
    let remainingIncreases: Int
    let maneuverFlips: Int

    init(_ frames: [ReplayFrame]) {
        hiddenRatio = Double(frames.filter { $0.progress == nil }.count) / Double(max(1, frames.count))
        visibilityToggles = zip(frames, frames.dropFirst()).filter { ($0.progress == nil) != ($1.progress == nil) }.count
        var jumps = 0, regressions = 0, regressionMeters = 0.0, increases = 0
        for (a, b) in zip(frames, frames.dropFirst()) {
            guard let p = a.progress, let q = b.progress, b.time.timeIntervalSince(a.time) <= 1.5 else { continue }
            let moved = q.distanceAlongRoute - p.distanceAlongRoute
            if abs(moved) > 3 { jumps += 1 }
            if moved < -0.5 {
                regressions += 1
                regressionMeters -= moved
            }
            if let before = p.remainingMeters, let after = q.remainingMeters, after - before > 1 { increases += 1 }
        }
        self.jumps = jumps
        regressionCount = regressions
        self.regressionMeters = regressionMeters
        remainingIncreases = increases
        var maneuvers: [(Date, RouteManeuver)] = []
        for frame in frames {
            guard let maneuver = frame.progress?.maneuver, maneuvers.last?.1 != maneuver else { continue }
            maneuvers.append((frame.time, maneuver))
        }
        maneuverFlips = maneuvers.indices.dropFirst(2).filter { index in
            maneuvers[index].1 == maneuvers[index - 2].1
                && maneuvers[index].0.timeIntervalSince(maneuvers[index - 2].0) <= 10
        }.count
    }

    var summary: String {
        String(format: "hidden=%.1f%% toggles=%d jumps=%d regressions=%d(%.1fm) remainingUp=%d flips=%d",
               hiddenRatio * 100, visibilityToggles, jumps, regressionCount, regressionMeters,
               remainingIncreases, maneuverFlips)
    }
}

private extension IndoorMapGeometry {
    var center: IndoorMapCoordinate {
        let points: [IndoorMapCoordinate] = switch self {
        case let .point(point): [point]
        case let .lineString(line): line
        case let .polygon(rings): rings.first ?? []
        case let .multiPolygon(polygons): polygons.first?.first ?? []
        }
        guard !points.isEmpty else { return .init(latitude: 0, longitude: 0) }
        return .init(latitude: points.map(\.latitude).reduce(0, +) / Double(points.count),
                     longitude: points.map(\.longitude).reduce(0, +) / Double(points.count))
    }
}
