import Foundation

nonisolated struct IndoorPosition: Equatable, Sendable {
    enum Source: Equatable, Sendable { case sensor, manual, replay }

    let coordinate: IndoorMapCoordinate
    let floorOrdinal: Int?
    let horizontalAccuracy: Double?
    let timestamp: Date
    let source: Source
    /// 진북이 0도이고 시계 방향으로 증가한다. 방향을 알 수 없으면 nil이다.
    let headingDegrees: Double?

    init(coordinate: IndoorMapCoordinate, floorOrdinal: Int?, horizontalAccuracy: Double?,
         timestamp: Date, source: Source, headingDegrees: Double? = nil) {
        self.coordinate = coordinate
        self.floorOrdinal = floorOrdinal
        self.horizontalAccuracy = horizontalAccuracy
        self.timestamp = timestamp
        self.source = source
        self.headingDegrees = headingDegrees.flatMap {
            $0.isFinite && (0..<360).contains($0) ? $0 : nil
        }
    }

    /// 표시·화면 중심 이동에만 쓴다. 경로 도착 판정이나 정확도 보장 기준이 아니다.
    func isRecent(at date: Date) -> Bool {
        guard coordinate.isValid else { return false }
        if source == .manual { return true }
        guard let horizontalAccuracy, horizontalAccuracy.isFinite, horizontalAccuracy >= 0 else { return false }
        return (-5...30).contains(date.timeIntervalSince(timestamp))
    }
}

nonisolated enum IndoorLocationAuthorization: Equatable, Sendable {
    case notDetermined, denied, restricted, authorized(precise: Bool), servicesDisabled

    var isAuthorized: Bool {
        if case .authorized = self { return true }
        return false
    }
}

nonisolated enum IndoorLocationEvent: Equatable, Sendable {
    case authorization(IndoorLocationAuthorization)
    case position(IndoorPosition)
    /// 위치 재수신을 기다리는 동안 완료된 경로 미리보기는 유지한다.
    case temporarilyUnavailable(String)
    case unavailable(String)
}
