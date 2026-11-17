import Foundation

/// 직전 매칭 이력을 함께 보고 경로 위 후보를 고른다(온라인 HMM).
/// - 방출: 측정 위치와 후보 사이 거리. 표준편차는 기기 보고 오차.
/// - 전이: 경로를 따라 간 거리와 직선 이동 거리의 차이. 걸을 수 없는 속도의 점프와 되돌아감은 불리하다.
nonisolated struct RouteMatcher: Equatable, Sendable {
    nonisolated struct Configuration: Equatable, Sendable {
        var matchingRadius = GuidanceEngine.matchingRadiusMeters
        var maximumWalkingSpeed = 2.5
        var minimumSigma = 2.0
        var transitionScale = 3.0
        var backwardPenalty = 1.5
        var backwardTolerance = 1.0
        /// 걸을 수 없는 점프만 연속으로 이만큼 들어오면 이력을 버리고 새로 시작한다.
        var restartAfterImpossibleCount = 3
        var ambiguousSeparation = 8.0
    }

    nonisolated enum Result: Equatable, Sendable {
        case matched(GuidanceEngine.Candidate)
        /// 이번 측정으로는 고를 수 없어 직전 추정을 유지한다.
        case held
        case offRoute
        case ambiguous
    }

    private struct Scored: Equatable, Sendable {
        let candidate: GuidanceEngine.Candidate
        let score: Double
    }

    let configuration: Configuration
    private var previous: [Scored] = []
    private var previousCoordinate: IndoorMapCoordinate?
    private var previousTime: Date?
    private var impossibleCount = 0

    init(configuration: Configuration = .init()) {
        self.configuration = configuration
    }

    var hasHistory: Bool { !previous.isEmpty }

    mutating func reset() {
        previous = []
        previousCoordinate = nil
        previousTime = nil
        impossibleCount = 0
    }

    mutating func match(_ candidates: [GuidanceEngine.Candidate], measured: IndoorMapCoordinate,
                        accuracy: Double, at time: Date) -> Result {
        let nearby = candidates.filter { $0.distance <= configuration.matchingRadius }
        guard !nearby.isEmpty else { return .offRoute }
        let sigma = max(configuration.minimumSigma, accuracy)
        func emission(_ candidate: GuidanceEngine.Candidate) -> Double {
            -(candidate.distance * candidate.distance) / (2 * sigma * sigma)
        }

        guard !previous.isEmpty, let previousCoordinate, let previousTime else {
            return start(with: nearby, measured: measured, accuracy: accuracy, at: time, emission: emission)
        }

        let dt = max(0.5, time.timeIntervalSince(previousTime))
        let straight = RoutingGeometry.distanceMeters(from: previousCoordinate, to: measured)
        var scored: [Scored] = []
        for candidate in nearby {
            var best = -Double.infinity
            for prior in previous {
                let moved = candidate.offset - prior.candidate.offset
                // 측정 오차만큼은 봐주고, 그래도 보행 속도를 넘으면 불가능한 전이로 본다.
                guard (abs(moved) - accuracy) / dt <= configuration.maximumWalkingSpeed else { continue }
                var transition = -abs(abs(moved) - straight) / configuration.transitionScale
                if moved < -configuration.backwardTolerance { transition -= configuration.backwardPenalty }
                best = max(best, prior.score + transition)
            }
            if best > -.infinity { scored.append(.init(candidate: candidate, score: best + emission(candidate))) }
        }

        guard let top = scored.max(by: { $0.score < $1.score }) else {
            impossibleCount += 1
            guard impossibleCount >= configuration.restartAfterImpossibleCount else { return .held }
            reset()
            return start(with: nearby, measured: measured, accuracy: accuracy, at: time, emission: emission)
        }
        impossibleCount = 0
        previous = scored.map { .init(candidate: $0.candidate, score: $0.score - top.score) }
        self.previousCoordinate = measured
        self.previousTime = time
        return .matched(top.candidate)
    }

    private mutating func start(with nearby: [GuidanceEngine.Candidate], measured: IndoorMapCoordinate,
                                accuracy: Double, at time: Date,
                                emission: (GuidanceEngine.Candidate) -> Double) -> Result {
        guard let closest = nearby.min(by: { $0.distance == $1.distance ? $0.index < $1.index : $0.distance < $1.distance })
        else { return .offRoute }
        // 첫 위치는 기존 규칙처럼, 비슷하게 가까운 후보가 경로상 멀리 떨어져 있으면 정하지 않는다.
        let close = nearby.filter { $0.distance <= closest.distance + max(0.25, min(accuracy, 1)) }
        if close.contains(where: {
            abs($0.offset - closest.offset) > configuration.ambiguousSeparation && abs($0.index - closest.index) > 1
        }) { return .ambiguous }
        let top = emission(closest)
        previous = nearby.map { .init(candidate: $0, score: emission($0) - top) }
        previousCoordinate = measured
        previousTime = time
        return .matched(closest)
    }
}
