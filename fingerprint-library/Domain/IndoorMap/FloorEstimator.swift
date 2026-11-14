import Foundation

/// 층 추정 결과. `ordinal`은 IMDF 층 ordinal(1층 = 0)이다.
nonisolated struct FloorEstimate: Equatable, Sendable {
    nonisolated enum Basis: Equatable, Sendable {
        case unknown    // 근거가 없어 층을 모름
        case measured   // CLFloor가 지금 같은 층을 보고함
        case held       // CLFloor 값이 비어 직전 추정을 유지함
        case corrected  // CLFloor는 다른 층을 보고하지만 추정을 유지함
    }

    let ordinal: Int?
    let basis: Basis
}

/// CLFloor(어느 층인가)와 기압계(몇 층 움직였나)를 합쳐 층을 추정한다.
/// 시간은 이벤트 자체의 시각을 쓴다: 층 관측은 CLLocation.timestamp, 기압 표본은 받은 시각.
nonisolated struct FloorEstimator: Equatable, Sendable {
    nonisolated struct Configuration: Equatable, Sendable {
        var validOrdinals: ClosedRange<Int> = 0...4
        // 기압계
        var floorHeightMeters = 4.5 // 미확정: 도서관 계단·엘리베이터의 기압 로그로 실측해야 한다.
        var transitionFraction = 0.6
        var transitionSamples = 2
        var restBandMeters = 1.2
        var baselineTimeConstant: TimeInterval = 60
        var slowBaselineTimeConstant: TimeInterval = 180
        var minimumPressureInterval: TimeInterval = 0.8
        var barometerLiveInterval: TimeInterval = 5
        var bridgeableGap: TimeInterval = 120
        // CLFloor 투표
        var voteMemoryWithBarometer: TimeInterval = 60
        var voteMemoryWithoutBarometer: TimeInterval = 3
        var warmupDuration: TimeInterval = 20
        var warmupWeight = 0.1
        var lagGrace: TimeInterval = 40
        var switchMargin = 1.0
        var maximumVoteCredit: TimeInterval = 2
        // 출력
        var holdWithoutBarometer: TimeInterval = 10
        var holdWithBarometer: TimeInterval = 120
    }

    var configuration: Configuration

    // 기압계 상태
    private var lastPressureTime: Date?
    private var altitudeWindow: [Double] = []
    private var smoothedAltitude: Double?
    private var baselineAltitude: Double?
    private var pendingDirection = 0
    private var pendingCount = 0
    private(set) var floorOffset = 0
    private var moveOrigin: Int?
    private var moveTime: Date?
    // 투표 상태
    private var votes: [Int: Double] = [:]
    private(set) var baseFloor: Int?
    private var lastFloorTime: Date?
    private var lastValidFloorTime: Date?
    private var lastRawLevel: Int?
    private var isWarmupPending = true
    private var warmupEnd: Date?

    init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    /// 표준 대기 공식. 절대 고도가 아니라 두 시각 사이의 높이 차이를 구하는 데만 쓴다.
    static func altitudeMeters(fromKilopascals pressure: Double) -> Double {
        44_330.8 * (1 - pow(pressure / 101.325, 0.190263))
    }

    /// 위치 업데이트를 새로 시작할 때 부른다. 다음 층 관측부터 준비 구간이 시작된다.
    mutating func locationUpdatesDidRestart() {
        isWarmupPending = true
    }

    mutating func ingestPressure(kilopascals: Double, at time: Date) {
        guard kilopascals.isFinite, kilopascals > 0 else { return }
        if let last = lastPressureTime,
           time.timeIntervalSince(last) < configuration.minimumPressureInterval { return }
        expireIfStale(at: time)
        let altitude = Self.altitudeMeters(fromKilopascals: kilopascals)
        let gap = lastPressureTime.map { time.timeIntervalSince($0) }
        lastPressureTime = time
        guard let gap, gap <= configuration.bridgeableGap, let baseline = baselineAltitude else {
            altitudeWindow = [altitude]
            smoothedAltitude = altitude
            baselineAltitude = altitude
            pendingDirection = 0
            pendingCount = 0
            return
        }
        if gap > configuration.barometerLiveInterval { altitudeWindow = [] }
        altitudeWindow = Array((altitudeWindow + [altitude]).suffix(3))
        let sorted = altitudeWindow.sorted()
        let smoothed = sorted.count == 3 ? sorted[1] : sorted.reduce(0, +) / Double(sorted.count)
        smoothedAltitude = smoothed

        let threshold = configuration.transitionFraction * configuration.floorHeightMeters
        let displacement = smoothed - baseline
        let direction = displacement >= threshold ? 1 : (displacement <= -threshold ? -1 : 0)
        guard direction != 0 else {
            pendingDirection = 0
            pendingCount = 0
            let timeConstant = abs(displacement) < configuration.restBandMeters
                ? configuration.baselineTimeConstant : configuration.slowBaselineTimeConstant
            baselineAltitude = baseline + displacement * min(1, gap / timeConstant)
            return
        }
        pendingCount = direction == pendingDirection ? pendingCount + 1 : 1
        pendingDirection = direction
        guard pendingCount >= configuration.transitionSamples else { return }
        pendingCount = configuration.transitionSamples

        var floorAltitude = baseline
        while (smoothed - floorAltitude) * Double(direction) >= threshold {
            if let current = currentFloor {
                let target = current + direction
                guard configuration.validOrdinals.contains(target) else {
                    // 지도에 없는 층: 층은 그대로 두고 기준 고도만 천천히 따라간다.
                    floorAltitude += (smoothed - floorAltitude)
                        * min(1, gap / configuration.slowBaselineTimeConstant)
                    break
                }
                if moveOrigin == nil { moveOrigin = current }
                moveTime = time
                if target == moveOrigin {
                    moveOrigin = nil
                    moveTime = nil
                }
            }
            floorOffset += direction
            floorAltitude += Double(direction) * configuration.floorHeightMeters
        }
        baselineAltitude = floorAltitude
    }

    /// `level`은 CLFloor.level(없으면 nil), `time`은 CLLocation.timestamp.
    /// 같은 시각이 다시 오면(나침반 갱신) 무시한다.
    mutating func ingestFloor(level: Int?, at time: Date) {
        if let last = lastFloorTime, time <= last { return }
        expireIfStale(at: time)
        var previousTime = lastFloorTime
        lastFloorTime = time
        if isWarmupPending {
            isWarmupPending = false
            warmupEnd = time.addingTimeInterval(configuration.warmupDuration)
            previousTime = nil
        }
        guard let level, configuration.validOrdinals.contains(level) else {
            lastRawLevel = nil
            return
        }
        lastRawLevel = level
        lastValidFloorTime = time
        var credit = previousTime.map { min(configuration.maximumVoteCredit, time.timeIntervalSince($0)) } ?? 1

        if let origin = moveOrigin, let moved = moveTime {
            if level == currentFloor {
                moveOrigin = nil
                moveTime = nil
            } else if level == origin {
                // CLFloor가 떠나온 층을 계속 보고함: 유예 시간 안이면 지연으로 보고 표에 넣지 않는다.
                if time.timeIntervalSince(moved) <= configuration.lagGrace { return }
                // 유예 시간이 지나도 그대로면 기압계의 이동 판단을 취소한다.
                if let current = currentFloor { floorOffset += origin - current }
                if let smoothedAltitude { baselineAltitude = smoothedAltitude }
                moveOrigin = nil
                moveTime = nil
            }
        }

        if let warmupEnd, time < warmupEnd { credit *= configuration.warmupWeight }
        let memory = isBarometerLive(at: time)
            ? configuration.voteMemoryWithBarometer : configuration.voteMemoryWithoutBarometer
        let keep = exp(-credit / memory)
        votes = votes.mapValues { $0 * keep }.filter { $0.value > 1e-6 }
        let candidate = level - floorOffset
        votes[candidate, default: 0] += credit

        guard let base = baseFloor else {
            baseFloor = candidate
            return
        }
        let mine = votes[base] ?? 0
        var best = base
        var bestWeight = mine
        for key in votes.keys.sorted() {
            if let weight = votes[key], weight > bestWeight {
                best = key
                bestWeight = weight
            }
        }
        if best != base, bestWeight > mine + configuration.switchMargin {
            baseFloor = best
            moveOrigin = nil
            moveTime = nil
        }
    }

    func estimate(at time: Date) -> FloorEstimate {
        guard !isStale(at: time), let current = currentFloor,
              configuration.validOrdinals.contains(current) else {
            return FloorEstimate(ordinal: nil, basis: .unknown)
        }
        if lastRawLevel == current { return FloorEstimate(ordinal: current, basis: .measured) }
        return FloorEstimate(ordinal: current, basis: lastRawLevel == nil ? .held : .corrected)
    }

    private var currentFloor: Int? { baseFloor.map { $0 + floorOffset } }

    private func isBarometerLive(at time: Date) -> Bool {
        guard let last = lastPressureTime else { return false }
        return abs(time.timeIntervalSince(last)) <= configuration.barometerLiveInterval
    }

    private func isStale(at time: Date) -> Bool {
        guard let last = lastValidFloorTime else { return false }
        let hasRecentPressure = lastPressureTime.map {
            time.timeIntervalSince($0) <= configuration.bridgeableGap
        } ?? false
        let limit = hasRecentPressure ? configuration.holdWithBarometer : configuration.holdWithoutBarometer
        return time.timeIntervalSince(last) > limit
    }

    private mutating func expireIfStale(at time: Date) {
        guard isStale(at: time) else { return }
        votes = [:]
        baseFloor = nil
        floorOffset = 0
        moveOrigin = nil
        moveTime = nil
        lastValidFloorTime = nil
    }
}
