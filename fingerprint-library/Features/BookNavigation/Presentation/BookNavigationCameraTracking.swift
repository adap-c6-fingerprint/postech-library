import Foundation

nonisolated struct BookNavigationCameraTracking: Equatable, Sendable {
    static let minimumSpanMeters = 12.0
    static let maximumLookAheadMeters = 30.0
    static let turnPreviewMeters = 8.0
    static let forwardThresholdMeters = 2.0
    static let backwardThresholdMeters = 5.0
    /// 같은 구간 안에서는 카메라를 이보다 자주 다시 맞추지 않는다.
    static let minimumIntervalSeconds = 2.0
    /// 이 값 이상이면 위치를 쓰지 않으므로 카메라도 따라가지 않는다.
    static let maximumAccuracyMeters = GuidanceTracker.Configuration().unusableAccuracy

    private var lastRemainingMeters: Double?
    private var lastCoordinate: IndoorMapCoordinate?
    private var lastMinimumSpanMeters: Double?
    private var lastStepIndex: Int?
    private var lastFocusAt: Date?

    mutating func focus(
        position: IndoorPosition,
        progress: RouteGuidanceProgress,
        plan: GuidanceEngine,
        floorID: UUID,
        uncertaintyMeters: Double? = nil,
        now: Date,
        force: Bool = false
    ) -> BookNavigationCameraFocus? {
        guard position.source != .manual, position.coordinate.isValid,
              progress.coordinate.isValid, (0...1).contains(progress.fraction),
              let remaining = progress.remainingMeters, remaining.isFinite, remaining >= 0,
              let accuracy = position.horizontalAccuracy, accuracy.isFinite,
              (0..<Self.maximumAccuracyMeters).contains(accuracy),
              position.floorOrdinal == plan.destination.level, floorID == plan.destination.floorID
        else { return nil }

        var remainingPath = [progress.coordinate]
        if !plan.steps.isEmpty {
            guard plan.steps.indices.contains(progress.stepIndex) else { return nil }
            let step = plan.steps[progress.stepIndex]
            let current = progress.fraction < 1 ? [step] : []
            let upcoming = Array(plan.steps.dropFirst(progress.stepIndex + 1))
            guard (current + upcoming).allSatisfy({
                $0.from.floorID == floorID && $0.to.floorID == floorID
            }) else { return nil }
            if progress.fraction < 1 {
                remainingPath += Self.remainingVertices(step.coordinates, fraction: progress.fraction)
            }
            remainingPath += upcoming.flatMap(\.coordinates)
        }
        remainingPath.append(plan.destination.coordinate)
        let lookAhead = min(remaining, Self.maximumLookAheadMeters,
                            max(Self.minimumSpanMeters, (progress.distanceToManeuver ?? remaining) + Self.turnPreviewMeters))
        // 원본 좌표 대신 안정화된 경로 위 위치를 기준으로 잡아, 측위가 흔들려도 화면이 따라 흔들리지 않게 한다.
        let coordinates = Self.prefix(remainingPath, meters: lookAhead)
        guard coordinates.allSatisfy(\.isValid) else { return nil }

        // 기기 보고 오차는 1초마다 크게 오르내리므로, 추정 불확실성이 있으면 그 값으로 화면 범위를 정한다.
        let spread = uncertaintyMeters.map { $0 * 2 } ?? accuracy
        let minimumSpan = max(Self.minimumSpanMeters, spread * 2 + 8)
        if !force, let previous = lastRemainingMeters, let lastCoordinate {
            let advance = previous - remaining
            let moved = RoutingGeometry.distanceMeters(from: lastCoordinate, to: progress.coordinate)
            let stepChanged = progress.stepIndex != lastStepIndex
            if !stepChanged, let lastFocusAt, now.timeIntervalSince(lastFocusAt) < Self.minimumIntervalSeconds {
                return nil
            }
            guard stepChanged
                || advance >= Self.forwardThresholdMeters
                || advance <= -Self.backwardThresholdMeters
                || (abs(advance) < 0.5 && moved >= max(3, accuracy))
                || minimumSpan > (lastMinimumSpanMeters ?? minimumSpan) + 1 else { return nil }
        }
        lastRemainingMeters = remaining
        lastCoordinate = progress.coordinate
        lastMinimumSpanMeters = minimumSpan
        lastStepIndex = progress.stepIndex
        lastFocusAt = now
        return .init(floorID: floorID, coordinates: coordinates,
                     minimumSpanMeters: minimumSpan)
    }

    private static func prefix(_ coordinates: [IndoorMapCoordinate], meters: Double) -> [IndoorMapCoordinate] {
        guard let first = coordinates.first else { return [] }
        var result = [first]
        var remaining = meters
        for (a, b) in zip(coordinates, coordinates.dropFirst()) {
            guard remaining > 0.000_001 else { break }
            let length = RoutingGeometry.distanceMeters(from: a, to: b)
            if length <= remaining {
                result.append(b)
                remaining -= length
            } else {
                let fraction = remaining / length
                result.append(.init(latitude: a.latitude + (b.latitude - a.latitude) * fraction,
                                    longitude: a.longitude + (b.longitude - a.longitude) * fraction))
                break
            }
        }
        return result
    }

    private static func remainingVertices(_ coordinates: [IndoorMapCoordinate], fraction: Double)
        -> [IndoorMapCoordinate] {
        let target = RoutingGeometry.polylineLengthMeters(coordinates) * fraction
        var walked = 0.0
        for index in coordinates.indices.dropFirst() {
            walked += RoutingGeometry.distanceMeters(from: coordinates[index - 1], to: coordinates[index])
            if walked > target + 0.000_001 { return Array(coordinates[index...]) }
        }
        return []
    }
}
