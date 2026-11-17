import Foundation

/// 진단 기록 한 세션의 요약 지표. 개선 전후·기기별 비교의 기준값이다.
nonisolated struct LocationDiagnosticsSummary: Codable, Equatable, Sendable {
    nonisolated struct Distribution: Codable, Equatable, Sendable {
        var count: Int
        var median: Double
        var p90: Double
        var max: Double

        init?(_ values: [Double]) {
            let sorted = values.filter(\.isFinite).sorted()
            guard let last = sorted.last else { return nil }
            count = sorted.count
            median = Self.percentile(sorted, 0.5)
            p90 = Self.percentile(sorted, 0.9)
            max = last
        }

        /// nearest-rank 백분위수
        static func percentile(_ sorted: [Double], _ fraction: Double) -> Double {
            let rank = Int((fraction * Double(sorted.count)).rounded(.up))
            return sorted[min(sorted.count - 1, Swift.max(0, rank - 1))]
        }
    }

    var durationSeconds: Double
    var locationCount: Int
    var updateIntervalSeconds: Distribution?
    var horizontalAccuracy: Distribution?

    // 튐
    var jumpCount: Int
    var jumpsPerMinute: Double
    var largestJumpMeters: Double
    var stationaryJumpCount: Int
    var stationarySpreadMeters: Distribution?
    var floorChangeCount: Int
    var jumpMarkerCount: Int

    // 실제 오차 (현장 마커 기준)
    var checkpointErrorMeters: Distribution?
    var walkingErrorMeters: Distribution?

    // 안내 안정성
    var guidanceQualityRatio: [String: Double]
    var guidanceSuspensionCount: Int
    var maneuverFlipCount: Int
    var remainingIncreaseCount: Int
    var progressRegressionCount: Int
    var progressRegressionMeters: Double
    var distanceToRouteMeters: Distribution?
    var cameraRecenterCount: Int

    /// 기록 목록에 보여 줄 한 줄 요약
    var headline: String {
        let accuracy = horizontalAccuracy.map { "오차 p90 ±\(Self.format($0.p90))m" } ?? "오차 없음"
        let jumps = "튐 \(jumpCount)회(\(Self.format(jumpsPerMinute))/분)"
        let flips = "안내 뒤집힘 \(maneuverFlipCount)회"
        return [accuracy, jumps, flips].joined(separator: " · ")
    }

    static func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }
}

nonisolated enum LocationDiagnosticsAnalyzer {
    static let maneuverFlipWindowSeconds = 10.0
    static let remainingIncreaseThresholdMeters = 1.0
    static let progressRegressionThresholdMeters = 0.5
    static let markerMatchWindowSeconds = 3.0
    static let walkingSegmentMaximumSeconds = 180.0
    static let stationaryMinimumSeconds = 10.0
    static let qualityWeightCapSeconds = 5.0

    static func summarize(_ records: [LocationDiagnosticsRecord]) -> LocationDiagnosticsSummary {
        var locations: [LocationDiagnosticsRecord.LocationSample] = []
        var guidance: [LocationDiagnosticsRecord.GuidanceSample] = []
        var activities: [LocationDiagnosticsRecord.ActivitySample] = []
        var markers: [LocationDiagnosticsRecord.Marker] = []
        for record in records {
            switch record {
            case let .location(value): locations.append(value)
            case let .guidance(value): guidance.append(value)
            case let .activity(value): activities.append(value)
            case let .marker(value): markers.append(value)
            case .heading, .motion, .event, .route: break
            }
        }
        locations.sort { $0.timestamp < $1.timestamp }
        guidance.sort { $0.at < $1.at }
        activities.sort { $0.startDate < $1.startDate }
        markers.sort { $0.at < $1.at }

        let times: [Date] = records.map(\.time)
        var duration = 0.0
        if let first = times.min(), let last = times.max() { duration = last.timeIntervalSince(first) }

        var intervals: [Double] = []
        var jumps: [LocationJump] = []
        var stationaryJumpCount = 0
        var floorChanges = 0
        for (previous, current) in zip(locations, locations.dropFirst()) {
            let seconds = current.timestamp.timeIntervalSince(previous.timestamp)
            guard seconds > 0 else { continue }
            intervals.append(seconds)
            let jump = LocationJump(meters: RoutingGeometry.distanceMeters(from: previous.coordinate, to: current.coordinate),
                                    seconds: seconds)
            if jump.isJump {
                jumps.append(jump)
                if isStationary(at: current.timestamp, activities) { stationaryJumpCount += 1 }
            }
            if let before = previous.floorLevel, let after = current.floorLevel, before != after { floorChanges += 1 }
        }

        let guidanceMetrics = guidanceStability(guidance)
        let errors = markerErrors(markers: markers, locations: locations)
        let accuracies: [Double] = locations.map(\.horizontalAccuracy).filter { $0 >= 0 }
        let jumpsPerMinute: Double = duration > 0 ? Double(jumps.count) / (duration / 60) : 0
        let largestJump: Double = jumps.map(\.meters).max() ?? 0
        let spreads = stationarySpreads(locations: locations, activities: activities)
        let jumpMarkers = markers.filter { $0.kind == .jump }.count
        let routeDistances: [Double] = guidance.compactMap(\.distanceToRoute)

        return LocationDiagnosticsSummary(
            durationSeconds: duration,
            locationCount: locations.count,
            updateIntervalSeconds: Distribution(intervals),
            horizontalAccuracy: Distribution(accuracies),
            jumpCount: jumps.count,
            jumpsPerMinute: jumpsPerMinute,
            largestJumpMeters: largestJump,
            stationaryJumpCount: stationaryJumpCount,
            stationarySpreadMeters: Distribution(spreads),
            floorChangeCount: floorChanges,
            jumpMarkerCount: jumpMarkers,
            checkpointErrorMeters: Distribution(errors.checkpoint),
            walkingErrorMeters: Distribution(errors.walking),
            guidanceQualityRatio: guidanceMetrics.qualityRatio,
            guidanceSuspensionCount: guidanceMetrics.suspensions,
            maneuverFlipCount: guidanceMetrics.flips,
            remainingIncreaseCount: guidanceMetrics.remainingIncreases,
            progressRegressionCount: guidanceMetrics.regressionCount,
            progressRegressionMeters: guidanceMetrics.regressionMeters,
            distanceToRouteMeters: Distribution(routeDistances),
            cameraRecenterCount: guidanceMetrics.cameraRecenters
        )
    }

    private typealias Distribution = LocationDiagnosticsSummary.Distribution

    // MARK: - 안내 안정성

    private struct GuidanceStability {
        var qualityRatio: [String: Double] = [:]
        var suspensions = 0
        var flips = 0
        var remainingIncreases = 0
        var regressionCount = 0
        var regressionMeters = 0.0
        var cameraRecenters = 0
    }

    private static func guidanceStability(_ samples: [LocationDiagnosticsRecord.GuidanceSample]) -> GuidanceStability {
        var result = GuidanceStability()
        var weights: [String: Double] = [:]
        for (index, sample) in samples.enumerated() {
            let next = samples.indices.contains(index + 1) ? samples[index + 1].at : sample.at.addingTimeInterval(1)
            weights[sample.quality, default: 0] += min(qualityWeightCapSeconds, max(0, next.timeIntervalSince(sample.at)))
        }
        let total = weights.values.reduce(0, +)
        if total > 0 { result.qualityRatio = weights.mapValues { $0 / total } }

        var maneuvers: [(at: Date, stopIndex: Int, value: String)] = []
        for (previous, current) in zip(samples, samples.dropFirst()) {
            if previous.quality == "on_route", current.quality != "on_route" { result.suspensions += 1 }
            if current.cameraRequestID > previous.cameraRequestID {
                result.cameraRecenters += current.cameraRequestID - previous.cameraRequestID
            }
            guard previous.stopIndex == current.stopIndex else { continue }
            if let before = previous.remainingMeters, let after = current.remainingMeters,
               after - before > remainingIncreaseThresholdMeters { result.remainingIncreases += 1 }
            if let before = previous.distanceAlongRoute, let after = current.distanceAlongRoute,
               before - after > progressRegressionThresholdMeters {
                result.regressionCount += 1
                result.regressionMeters += before - after
            }
        }
        for sample in samples {
            guard let maneuver = sample.maneuver else { continue }
            if maneuvers.last?.value == maneuver, maneuvers.last?.stopIndex == sample.stopIndex { continue }
            maneuvers.append((sample.at, sample.stopIndex, maneuver))
        }
        // A → B → A 가 짧은 시간 안에 일어나면 안내가 뒤집힌 것으로 센다.
        for index in maneuvers.indices.dropFirst(2) {
            let first = maneuvers[index - 2], middle = maneuvers[index - 1], last = maneuvers[index]
            if first.stopIndex == last.stopIndex, middle.stopIndex == last.stopIndex,
               first.value == last.value, middle.value != last.value,
               last.at.timeIntervalSince(first.at) <= maneuverFlipWindowSeconds { result.flips += 1 }
        }
        return result
    }

    // MARK: - 실제 오차

    private static func markerErrors(
        markers: [LocationDiagnosticsRecord.Marker],
        locations: [LocationDiagnosticsRecord.LocationSample]
    ) -> (checkpoint: [Double], walking: [Double]) {
        let truths = markers.filter { $0.kind != .jump && $0.coordinate != nil }
        var checkpoint: [Double] = []
        for marker in truths {
            guard let truth = marker.coordinate,
                  let nearest = locations.min(by: {
                      abs($0.timestamp.timeIntervalSince(marker.at)) < abs($1.timestamp.timeIntervalSince(marker.at))
                  }), abs(nearest.timestamp.timeIntervalSince(marker.at)) <= markerMatchWindowSeconds,
                  marker.floorOrdinal == nil || nearest.floorLevel == nil || marker.floorOrdinal == nearest.floorLevel
            else { continue }
            checkpoint.append(RoutingGeometry.distanceMeters(from: nearest.coordinate, to: truth))
        }

        // 연속된 두 기준점 사이를 일정한 속도로 걸었다고 보고 시간 비율로 정답 위치를 보간한다.
        var walking: [Double] = []
        for (start, end) in zip(truths, truths.dropFirst()) {
            guard let from = start.coordinate, let to = end.coordinate,
                  start.floorOrdinal == end.floorOrdinal else { continue }
            let span = end.at.timeIntervalSince(start.at)
            guard span > 0, span <= walkingSegmentMaximumSeconds else { continue }
            for sample in locations where sample.timestamp > start.at && sample.timestamp < end.at {
                if let floor = start.floorOrdinal, let level = sample.floorLevel, floor != level { continue }
                let fraction = sample.timestamp.timeIntervalSince(start.at) / span
                let truth = IndoorMapCoordinate(latitude: from.latitude + (to.latitude - from.latitude) * fraction,
                                                longitude: from.longitude + (to.longitude - from.longitude) * fraction)
                walking.append(RoutingGeometry.distanceMeters(from: sample.coordinate, to: truth))
            }
        }
        return (checkpoint, walking)
    }

    // MARK: - 정지 상태

    static func isStationary(at date: Date, _ activities: [LocationDiagnosticsRecord.ActivitySample]) -> Bool {
        guard let activity = activities.last(where: { $0.startDate <= date }) else { return false }
        return activity.isStationary && activity.confidence >= 1
    }

    /// 정지가 10초 이상 이어진 구간마다 위치가 중심에서 흩어진 정도(RMS, m)
    private static func stationarySpreads(
        locations: [LocationDiagnosticsRecord.LocationSample],
        activities: [LocationDiagnosticsRecord.ActivitySample]
    ) -> [Double] {
        var segments: [[LocationDiagnosticsRecord.LocationSample]] = []
        var current: [LocationDiagnosticsRecord.LocationSample] = []
        for sample in locations {
            if isStationary(at: sample.timestamp, activities),
               current.last.map({ $0.floorLevel == sample.floorLevel }) ?? true {
                current.append(sample)
            } else {
                if !current.isEmpty { segments.append(current) }
                current = isStationary(at: sample.timestamp, activities) ? [sample] : []
            }
        }
        if !current.isEmpty { segments.append(current) }
        return segments.compactMap { segment in
            guard segment.count >= 2, let first = segment.first, let last = segment.last,
                  last.timestamp.timeIntervalSince(first.timestamp) >= stationaryMinimumSeconds else { return nil }
            let latitude = segment.map(\.latitude).reduce(0, +) / Double(segment.count)
            let longitude = segment.map(\.longitude).reduce(0, +) / Double(segment.count)
            let center = IndoorMapCoordinate(latitude: latitude, longitude: longitude)
            let squared = segment.map { pow(RoutingGeometry.distanceMeters(from: $0.coordinate, to: center), 2) }
            return sqrt(squared.reduce(0, +) / Double(segment.count))
        }
    }
}
