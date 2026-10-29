import Foundation

/// 거리 기반 예상치다. 만보기의 실측 걸음 수나 안내 단계 수와 구분한다.
nonisolated struct BookNavigationMetrics: Equatable, Sendable {
    static let walkingMetersPerHour = 5_000.0
    static let estimatedStepLengthMeters = 0.7
    let minutes: Int
    let steps: Int

    init?(remainingMeters: Double) {
        guard remainingMeters.isFinite, remainingMeters >= 0,
              let minutes = Int(exactly: (remainingMeters * 60 / Self.walkingMetersPerHour).rounded()),
              let steps = Int(exactly: (remainingMeters / Self.estimatedStepLengthMeters).rounded(.up)) else { return nil }
        self.minutes = minutes
        self.steps = steps
    }
}
