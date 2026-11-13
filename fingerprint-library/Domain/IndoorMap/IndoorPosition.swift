import Foundation

nonisolated struct IndoorPosition: Equatable, Sendable {
    enum Source: Equatable, Sendable { case sensor, manual, replay }

    let coordinate: IndoorMapCoordinate
    let floorOrdinal: Int?
    let horizontalAccuracy: Double?
    let timestamp: Date
    let source: Source
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
    case temporarilyUnavailable(String)
    case unavailable(String)
}
