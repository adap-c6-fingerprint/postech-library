import Foundation

nonisolated struct IndoorPosition: Equatable, Sendable {
    enum Source: Equatable, Sendable { case sensor, manual, replay, simulation }

    let coordinate: IndoorMapCoordinate
    let floorOrdinal: Int?
    let horizontalAccuracy: Double?
    let timestamp: Date
    let source: Source

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
    case unavailable(String)
}
