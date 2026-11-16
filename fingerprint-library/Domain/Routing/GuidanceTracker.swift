import Foundation

/// 위치 측정값을 시간에 걸쳐 모아 안내용 진행 상태를 추정한다.
/// - 오차는 버리지 않고 가중치로 쓴다(`AlongRouteFilter`).
/// - 경로 후보는 직전 이력과 함께 고른다(`RouteMatcher`).
/// - 오차가 잠깐 커져도 안내를 바로 멈추지 않고, 오래 나쁠 때만 위치를 잃은 것으로 본다.
/// 층 판정은 하지 않는다. 호출하는 쪽이 정한 층을 입력으로 받는다.
nonisolated struct GuidanceTracker: Equatable, Sendable {
    nonisolated struct Configuration: Equatable, Sendable {
        /// 이 값 미만이면 좋은 측정값이다.
        var goodAccuracy = 10.0
        /// 이 값 이상이면 측정값을 쓰지 않는다.
        var unusableAccuracy = 15.0
        /// 쓸 수 없는 측정값이 이 시간 넘게 이어지면 위치를 잃은 것으로 본다.
        var lostAfterSeconds = 3.0
        /// 좋은 측정값이 이만큼 연속되면 다시 추적 중으로 본다.
        var recoveryCount = 2
        /// 측정값 없이 이 시간이 지나면 멈췄을 수도 있으므로 속도를 줄인다.
        var dampAfterSeconds = 2.0
        /// 오차가 큰 측정값이 들어올 때마다 남기는 속도 비율
        var degradedSpeedRetention = 0.6
        var filter = AlongRouteFilter.Configuration()
        var matcher = RouteMatcher.Configuration()
    }

    nonisolated enum Status: Equatable, Sendable {
        case tracking
        /// 측정 오차가 커서 추정에 기대고 있다. 안내는 계속한다.
        case degraded
        /// 쓸 만한 측정값이 오래 없다. 안내를 멈춰야 한다.
        case lost
    }

    let engine: GuidanceEngine
    let configuration: Configuration
    private(set) var status: Status = .lost
    private var matcher: RouteMatcher
    private var filter: AlongRouteFilter?
    private var range: ClosedRange<Double>?
    private var level: Int?
    private var unusableSince: Date?
    private var goodCount = 0
    private var lastUpdate: Date?
    private var lastMeasurement: Date?

    /// 진행 거리 추정의 표준편차(m). 아직 추정이 없으면 nil
    var uncertaintyMeters: Double? { filter?.uncertainty }

    init(engine: GuidanceEngine, configuration: Configuration = .init()) {
        self.engine = engine
        self.configuration = configuration
        matcher = RouteMatcher(configuration: configuration.matcher)
    }

    mutating func reset() {
        status = .lost
        matcher.reset()
        filter = nil
        range = nil
        level = nil
        unusableSince = nil
        goodCount = 0
        lastUpdate = nil
        lastMeasurement = nil
    }

    mutating func update(position: IndoorPosition, at now: Date, anchor: PositionAnchor? = nil) -> GuidanceEstimate {
        guard position.source != .manual, position.coordinate.isValid,
              let accuracy = position.horizontalAccuracy, accuracy.isFinite, accuracy >= 0 else {
            return estimate(issue: .invalidPosition)
        }
        guard (-2...GuidanceEngine.maximumPositionAge).contains(now.timeIntervalSince(position.timestamp)) else {
            return estimate(issue: .stalePosition)
        }
        guard let level = position.floorOrdinal else {
            reset()
            return estimate(issue: .unknownFloor)
        }
        if self.level != level {
            reset()
            self.level = level
        }
        if engine.steps.isEmpty {
            return destinationOnlyEstimate(position: position, now: now)
        }

        updateStatus(accuracy: accuracy, at: position.timestamp)
        if var filter, let lastUpdate {
            let dt = position.timestamp.timeIntervalSince(lastUpdate)
            filter.predict(dt: dt)
            if let lastMeasurement, position.timestamp.timeIntervalSince(lastMeasurement) > configuration.dampAfterSeconds {
                filter.dampSpeed(0.5)
            } else if accuracy >= configuration.goodAccuracy {
                // 오차가 큰 동안 직전 속도로 계속 앞서 나가면, 멈춘 사람보다 점이 앞서 갔다가 되돌아온다.
                filter.dampSpeed(configuration.degradedSpeedRetention)
            }
            if let range { filter.clamp(to: range) }
            self.filter = filter
        }
        lastUpdate = max(lastUpdate ?? position.timestamp, position.timestamp)

        var measured = position.coordinate
        if let anchor, anchor.isValid(at: now, floorOrdinal: level, near: position.coordinate) {
            measured = anchor.corrected(position.coordinate)
        }

        guard accuracy < configuration.unusableAccuracy else {
            return estimate(measuredFrom: measured, level: level, issue: filter == nil ? .inaccuratePosition : nil)
        }

        let candidates = engine.candidates(near: measured, level: level)
        guard !candidates.isEmpty else { return estimate(issue: .unknownFloor) }
        switch matcher.match(candidates, measured: measured, accuracy: accuracy, at: position.timestamp) {
        case let .matched(candidate):
            let range = engine.walkableRange(around: candidate, level: level)
            self.range = range
            if var filter {
                filter.update(measured: candidate.offset, accuracy: accuracy)
                filter.clamp(to: range)
                self.filter = filter
            } else {
                var filter = AlongRouteFilter(distance: candidate.offset, accuracy: accuracy,
                                              configuration: configuration.filter)
                filter.clamp(to: range)
                self.filter = filter
            }
            lastMeasurement = position.timestamp
            return estimate(measuredFrom: measured, level: level, matched: candidate)
        case .held:
            return estimate(measuredFrom: measured, level: level)
        case .offRoute:
            return estimate(issue: .offRoute)
        case .ambiguous:
            return estimate(issue: .ambiguousPosition)
        }
    }

    private mutating func updateStatus(accuracy: Double, at time: Date) {
        if accuracy >= configuration.unusableAccuracy {
            goodCount = 0
            let since = unusableSince ?? time
            unusableSince = since
            if time.timeIntervalSince(since) >= configuration.lostAfterSeconds || filter == nil {
                status = .lost
            } else if status == .tracking {
                status = .degraded
            }
            return
        }
        unusableSince = nil
        if accuracy < configuration.goodAccuracy {
            goodCount += 1
            if goodCount >= configuration.recoveryCount || filter == nil { status = .tracking } else { status = .degraded }
        } else {
            goodCount = 0
            status = .degraded
        }
    }

    private func estimate(issue: RouteGuidanceError) -> GuidanceEstimate {
        .init(status: status, progress: nil, uncertaintyMeters: filter?.uncertainty, issue: issue)
    }

    private func estimate(measuredFrom coordinate: IndoorMapCoordinate, level: Int,
                          matched: GuidanceEngine.Candidate? = nil, issue: RouteGuidanceError? = nil) -> GuidanceEstimate {
        guard let filter else {
            return .init(status: status, progress: nil, uncertaintyMeters: nil, issue: issue ?? .inaccuratePosition)
        }
        guard let point = engine.candidate(atDistance: filter.distance, level: level, measuredFrom: coordinate) else {
            return .init(status: status, progress: nil, uncertaintyMeters: filter.uncertainty, issue: .unknownFloor)
        }
        // 층 이동 지점에 맞춰졌다면 층 이동 안내를 유지하도록 그 후보를 그대로 쓴다.
        let target = matched.map { engine.steps[$0.index].changesFloor ? $0 : point } ?? point
        return .init(status: status, progress: engine.progress(at: target), uncertaintyMeters: filter.uncertainty,
                     issue: issue)
    }

    private mutating func destinationOnlyEstimate(position: IndoorPosition, now: Date) -> GuidanceEstimate {
        do {
            let progress = try engine.progress(for: position, at: now)
            status = .tracking
            return .init(status: status, progress: progress, uncertaintyMeters: nil, issue: nil)
        } catch {
            return estimate(issue: error as? RouteGuidanceError ?? .invalidPosition)
        }
    }
}

nonisolated struct GuidanceEstimate: Equatable, Sendable {
    let status: GuidanceTracker.Status
    /// 안정화된 진행 상태. 위치를 잃었어도 마지막 추정이 있으면 남긴다.
    let progress: RouteGuidanceProgress?
    /// 진행 거리 추정의 표준편차(m)
    let uncertaintyMeters: Double?
    let issue: RouteGuidanceError?
}
