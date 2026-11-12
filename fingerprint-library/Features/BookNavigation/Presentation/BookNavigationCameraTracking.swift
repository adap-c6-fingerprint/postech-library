import Foundation

/// 이미 검증된 안내 진행을 화면 범위로 바꾼다. 위치 판정이나 경로 계산은 하지 않는다.
nonisolated struct BookNavigationCameraTracking: Equatable, Sendable {
    // 실내 지도 표시용 기본값. 디자인·현장 확인 후 조정할 수 있다.
    static let minimumSpanMeters = 12.0
    static let maximumLookAheadMeters = 30.0
    static let turnPreviewMeters = 8.0
    static let forwardThresholdMeters = 2.0
    static let backwardThresholdMeters = 5.0

    private var lastRemainingMeters: Double?
    private var lastCoordinate: IndoorMapCoordinate?
    private var lastMinimumSpanMeters: Double?
    private var lastStepIndex: Int?

    mutating func focus(
        position: IndoorPosition,
        progress: RouteGuidanceProgress,
        plan: GuidanceEngine,
        floorID: UUID,
        force: Bool = false
    ) -> BookNavigationCameraFocus? {
        guard position.source != .manual, position.coordinate.isValid,
              progress.coordinate.isValid, (0...1).contains(progress.fraction),
              let remaining = progress.remainingMeters, remaining.isFinite, remaining >= 0,
              let accuracy = position.horizontalAccuracy, accuracy.isFinite,
              (0...GuidanceEngine.maximumAccuracyMeters).contains(accuracy),
              position.floorOrdinal == plan.destination.level, floorID == plan.destination.floorID
        else { return nil }

        var remainingPath = [progress.coordinate]
        if !plan.steps.isEmpty {
            guard plan.steps.indices.contains(progress.stepIndex) else { return nil }
            let step = plan.steps[progress.stepIndex]
            let current = progress.fraction < 1 ? [step] : []
            let upcoming = Array(plan.steps.dropFirst(progress.stepIndex + 1))
            // 다른 층의 서가가 평면상 가까워 보여도 확대하지 않는다.
            guard (current + upcoming).allSatisfy({
                $0.from.floorID == floorID && $0.to.floorID == floorID
            }) else { return nil }
            if progress.fraction < 1 {
                remainingPath += Self.remainingVertices(step.coordinates, fraction: progress.fraction)
            }
            remainingPath += upcoming.flatMap(\.coordinates)
        }
        remainingPath.append(plan.destination.coordinate)
        // 먼 뒤쪽 통로가 지도 외곽을 고정하지 않도록 다음 안내 지점과 회전 뒤 일부만 보여 준다.
        let lookAhead = min(remaining, Self.maximumLookAheadMeters,
                            max(Self.minimumSpanMeters, (progress.distanceToManeuver ?? remaining) + Self.turnPreviewMeters))
        let coordinates = [position.coordinate] + Self.prefix(remainingPath, meters: lookAhead)
        guard coordinates.allSatisfy(\.isValid) else { return nil }

        let minimumSpan = max(Self.minimumSpanMeters, accuracy * 2 + 8)
        if !force, let previous = lastRemainingMeters, let lastCoordinate {
            let advance = previous - remaining
            let moved = RoutingGeometry.distanceMeters(from: lastCoordinate, to: position.coordinate)
            guard progress.stepIndex != lastStepIndex
                || advance >= Self.forwardThresholdMeters
                || advance <= -Self.backwardThresholdMeters
                || (abs(advance) < 0.5 && moved >= max(3, accuracy))
                || minimumSpan > (lastMinimumSpanMeters ?? minimumSpan) + 1 else { return nil }
        }
        lastRemainingMeters = remaining
        lastCoordinate = position.coordinate
        lastMinimumSpanMeters = minimumSpan
        lastStepIndex = progress.stepIndex
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

    /// 현재 구간의 지난 꼭짓점을 제외해 긴 통로 중간에서도 점차 확대한다.
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
