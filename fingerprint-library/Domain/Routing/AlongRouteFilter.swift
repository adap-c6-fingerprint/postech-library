import Foundation

/// 경로 위 진행 거리와 속도를 함께 추정하는 1차원 칼만 필터.
/// 측정값을 정확도로 가중해 반영하므로, 오차가 큰 위치도 버리지 않고 조금만 믿는다.
nonisolated struct AlongRouteFilter: Equatable, Sendable {
    nonisolated struct Configuration: Equatable, Sendable {
        /// 보행 가속도 잡음(m/s²). 클수록 속도 변화를 빨리 따라간다.
        var accelerationNoise = 0.6
        /// 기기 보고 오차에 곱하는 값. 경로에 투영하면 수직 방향 오차가 빠지므로 1보다 작게 둔다.
        var measurementScale = 0.6
        var minimumMeasurementMeters = 1.0
        var speedRange: ClosedRange<Double> = -0.8...2.5
    }

    let configuration: Configuration
    private(set) var distance: Double
    private(set) var speed = 0.0
    private var p00: Double
    private var p01 = 0.0
    private var p11 = 1.0

    init(distance: Double, accuracy: Double, configuration: Configuration = .init()) {
        self.configuration = configuration
        self.distance = distance
        let sigma = max(configuration.minimumMeasurementMeters, accuracy * configuration.measurementScale)
        p00 = sigma * sigma
    }

    /// 추정 진행 거리의 표준편차(m)
    var uncertainty: Double { sqrt(max(0, p00)) }

    mutating func predict(dt: Double) {
        guard dt > 0, dt.isFinite else { return }
        distance += speed * dt
        let q = configuration.accelerationNoise * configuration.accelerationNoise
        let n00 = p00 + 2 * dt * p01 + dt * dt * p11 + q * dt * dt * dt / 3
        let n01 = p01 + dt * p11 + q * dt * dt / 2
        let n11 = p11 + q * dt
        (p00, p01, p11) = (n00, n01, n11)
    }

    mutating func update(measured: Double, accuracy: Double) {
        guard measured.isFinite, accuracy.isFinite else { return }
        let sigma = max(configuration.minimumMeasurementMeters, accuracy * configuration.measurementScale)
        let innovation = measured - distance
        let s = p00 + sigma * sigma
        let k0 = p00 / s, k1 = p01 / s
        distance += k0 * innovation
        speed += k1 * innovation
        speed = min(configuration.speedRange.upperBound, max(configuration.speedRange.lowerBound, speed))
        let n00 = (1 - k0) * p00
        let n01 = (1 - k0) * p01
        let n11 = p11 - k1 * p01
        (p00, p01, p11) = (n00, n01, max(0, n11))
    }

    /// 위치가 한동안 오지 않으면 멈췄을 수도 있으므로 속도를 줄인다.
    mutating func dampSpeed(_ factor: Double) {
        speed *= min(1, max(0, factor))
    }

    mutating func clamp(to range: ClosedRange<Double>) {
        if distance < range.lowerBound {
            distance = range.lowerBound
            speed = max(0, speed)
        } else if distance > range.upperBound {
            distance = range.upperBound
            speed = min(0, speed)
        }
    }
}
