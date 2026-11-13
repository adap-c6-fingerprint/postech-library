import Foundation

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
