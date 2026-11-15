import Foundation

/// 층 추정 결과. `ordinal`은 IMDF 층 ordinal(1층 = 0)이다.
nonisolated struct FloorEstimate: Equatable, Sendable {
    nonisolated enum Basis: Equatable, Sendable {
        case unknown      // 근거가 없어 층을 모름
        case unconfirmed  // 층은 내보내지만 표가 아직 갈려 있음 (시작 직후, 중앙 공간 근처, 기압계 없음)
        case measured     // CLFloor가 지금 같은 층을 보고함
        case held         // CLFloor 값이 비어 직전 추정을 유지함
        case corrected    // CLFloor는 다른 층을 보고하지만 추정을 유지함
    }

    let ordinal: Int?
    let basis: Basis
}

/// CLFloor(어느 층인가)와 기압계(몇 층 움직였나)를 합쳐 층을 추정한다.
/// 현재 층 = 기준층(CLFloor 투표) + 층 이동량(기압계).
/// 시간은 이벤트 자체의 시각을 쓴다: 층 관측은 CLLocation.timestamp, 기압 표본은 받은 시각.
nonisolated struct FloorEstimator: Equatable, Sendable {
    nonisolated struct Configuration: Equatable, Sendable {
        var validOrdinals: ClosedRange<Int> = 0...4
        // 기압계: 층 이동량 (2026-11-15 도서관 실측)
        var floorHeightMeters = 4.26
        var transitionFraction = 0.6
        var transitionSamples = 2
        var restBandMeters = 1.2
        var baselineTimeConstant: TimeInterval = 60
        var slowBaselineTimeConstant: TimeInterval = 180
        var minimumAltitudeInterval: TimeInterval = 0.8
        var barometerLiveInterval: TimeInterval = 5
        var bridgeableGap: TimeInterval = 120
        // CLFloor: 기준층 투표
        var voteMemoryWithBarometer: TimeInterval = 120
        var voteMemoryWithoutBarometer: TimeInterval = 3
        var warmupDuration: TimeInterval = 20
        var warmupWeight = 0.1
        var lagGrace: TimeInterval = 40
        var maximumVoteCredit: TimeInterval = 5
        var initialSwitchRatio = 1.0   // 최초 확정 전: 표가 더 많은 층을 바로 따른다 (지킬 층이 아직 없음)
        var switchRatio = 1.5          // 최초 확정 뒤: 다른 층이 기준층 표의 1.5배를 넘어야 바꾼다
        var confirmLead = 10.0
        // 출력
        var holdWithoutBarometer: TimeInterval = 10
        var holdWithBarometer: TimeInterval = 120
    }

    var configuration: Configuration

    // 기압계 상태
    private var lastAltitudeTime: Date?
    private var altitudeWindow: [Double] = []
    private var baselineAltitude: Double?
    private var pendingDirection = 0
    private var pendingCount = 0
    private(set) var floorOffset = 0
    private var moveOrigin: Int?
    private var moveTime: Date?
    // 투표 상태
    private(set) var votes: [Int: Double] = [:]
    private(set) var baseFloor: Int?
    private(set) var hasConfirmedFloor = false  // 마지막 초기화 뒤 한 번이라도 확정됐는가
    private var lastFloorTime: Date?
    private var lastValidFloorTime: Date?
    private var lastRawLevel: Int?
    private var isWarmupPending = true
    private var warmupEnd: Date?

    init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    /// 표준 대기 공식. 절대 고도가 아니라 두 시각 사이의 높이 차이를 구하는 데만 쓴다.
    /// 유한한 양수가 아니면 nil.
    static func altitudeMeters(fromKilopascals pressure: Double) -> Double? {
        guard pressure.isFinite, pressure > 0 else { return nil }
        return 44_330.8 * (1 - pow(pressure / 101.325, 0.190263))
    }

    /// 위치 업데이트를 새로 시작할 때 부른다. 다음 층 관측부터 준비 구간이 시작된다.
    mutating func locationUpdatesDidRestart() {
        isWarmupPending = true
    }

    /// 기압 표본을 높이(m)로 바꿔 넣는다. 약 1초 간격.
    mutating func ingestAltitude(meters altitude: Double, at time: Date) {
        guard altitude.isFinite else { return }
        if let last = lastAltitudeTime,
           time.timeIntervalSince(last) < configuration.minimumAltitudeInterval { return }
        expireIfStale(at: time)
        let gap = lastAltitudeTime.map { time.timeIntervalSince($0) }
        lastAltitudeTime = time
        guard let gap, gap <= configuration.bridgeableGap, let baseline = baselineAltitude else {
            altitudeWindow = [altitude]
            baselineAltitude = altitude
            pendingDirection = 0
            pendingCount = 0
            return
        }
        if gap > configuration.barometerLiveInterval { altitudeWindow = [] }
        altitudeWindow = Array((altitudeWindow + [altitude]).suffix(3))
        let sorted = altitudeWindow.sorted()
        let smoothed = sorted.count == 3 ? sorted[1] : sorted.reduce(0, +) / Double(sorted.count)

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

    /// `level`은 CLFloor.level(없으면 nil), `trust`는 `AtriumZone.trust(at:)`(0...1),
    /// `time`은 CLLocation.timestamp. 같은 시각이 다시 오면(나침반 갱신) 무시한다.
    mutating func ingestFloor(level: Int?, trust: Double = 1, at time: Date) {
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

        if let origin = moveOrigin, let moved = moveTime {
            let elapsed = time.timeIntervalSince(moved)
            if level == currentFloor {
                moveOrigin = nil
                moveTime = nil
            } else if level == origin, elapsed <= configuration.lagGrace {
                return  // CLFloor가 아직 떠나온 층을 보고함: 지연으로 보고 표에 넣지 않는다.
            } else if elapsed > configuration.lagGrace {
                moveOrigin = nil  // 유예가 끝나면 기록만 지운다. 기압계의 이동은 되돌리지 않는다.
                moveTime = nil
            }
        }

        let credit = previousTime.map { min(configuration.maximumVoteCredit, time.timeIntervalSince($0)) } ?? 1
        let isLive = isBarometerLive(at: time)
        // 중앙 공간 가중치는 기압계가 살아 있을 때만 쓴다. 기압계 없이는 실제 이동과 간섭을
        // 구분할 수 없으므로, 기압계가 없으면 원본 관측을 같은 무게로 반영한다.
        var weight = credit * (isLive ? min(1, max(0, trust)) : 1)
        if let warmupEnd, time < warmupEnd { weight *= configuration.warmupWeight }
        let memory = isLive ? configuration.voteMemoryWithBarometer : configuration.voteMemoryWithoutBarometer
        let keep = exp(-weight / memory)  // 가벼운 관측은 예전 표도 조금만 줄인다.
        votes = votes.mapValues { $0 * keep }.filter { $0.value > 1e-6 }
        let candidate = level - floorOffset
        votes[candidate, default: 0] += weight

        guard let base = baseFloor else {
            baseFloor = candidate
            return
        }
        let mine = votes[base] ?? 0
        var best = base
        var bestWeight = mine
        for key in votes.keys.sorted() {
            if let candidateWeight = votes[key], candidateWeight > bestWeight {
                best = key
                bestWeight = candidateWeight
            }
        }
        // 최초 확정 전에는 지킬 층이 없으므로 표가 더 많은 층을 따른다.
        let ratio = hasConfirmedFloor ? configuration.switchRatio : configuration.initialSwitchRatio
        if best != base, bestWeight > mine * ratio {
            baseFloor = best
            moveOrigin = nil
            moveTime = nil
        }
        if !hasConfirmedFloor, isConfirmed { hasConfirmedFloor = true }
    }

    func estimate(at time: Date) -> FloorEstimate {
        guard !isStale(at: time), let current = currentFloor,
              configuration.validOrdinals.contains(current) else {
            return FloorEstimate(ordinal: nil, basis: .unknown)
        }
        guard isConfirmed else { return FloorEstimate(ordinal: current, basis: .unconfirmed) }
        if lastRawLevel == current { return FloorEstimate(ordinal: current, basis: .measured) }
        return FloorEstimate(ordinal: current, basis: lastRawLevel == nil ? .held : .corrected)
    }

    /// 기준층의 표가 2등보다 `confirmLead` 이상 많은가.
    var isConfirmed: Bool { baseFloor != nil && lead >= configuration.confirmLead }

    /// 기준층 표 − 2등 후보 표. 기준층이 없으면 0.
    var lead: Double {
        guard let base = baseFloor else { return 0 }
        let mine = votes[base] ?? 0
        let runnerUp = votes.filter { $0.key != base }.values.max() ?? 0
        return mine - runnerUp
    }

    private var currentFloor: Int? { baseFloor.map { $0 + floorOffset } }

    private func isBarometerLive(at time: Date) -> Bool {
        guard let last = lastAltitudeTime else { return false }
        return abs(time.timeIntervalSince(last)) <= configuration.barometerLiveInterval
    }

    private func isStale(at time: Date) -> Bool {
        guard let last = lastValidFloorTime else { return false }
        let hasRecentAltitude = lastAltitudeTime.map {
            time.timeIntervalSince($0) <= configuration.bridgeableGap
        } ?? false
        let limit = hasRecentAltitude ? configuration.holdWithBarometer : configuration.holdWithoutBarometer
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
        hasConfirmedFloor = false                                         // 다시 "처음 층을 정하는" 단계
    }
}
