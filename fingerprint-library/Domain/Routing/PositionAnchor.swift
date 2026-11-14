import Foundation

/// 사용자가 실제 위치를 확인한 순간(목적지 서가 앞)의 측위 편향.
/// 같은 층에서 짧은 시간·거리 안에서만 다음 측정값을 보정한다. 구역이 바뀌면 편향도 바뀌므로 오래 쓰지 않는다.
nonisolated struct PositionAnchor: Equatable, Sendable {
    static let maximumOffsetMeters = 25.0
    static let lifetimeSeconds = 120.0
    static let rangeMeters = 30.0

    let northMeters: Double
    let eastMeters: Double
    let measuredCoordinate: IndoorMapCoordinate
    let floorOrdinal: Int
    let anchoredAt: Date

    /// 측정 위치와 실제 위치가 너무 멀면 확인 시점이 어긋난 것으로 보고 만들지 않는다.
    init?(actual: IndoorMapCoordinate, measured: IndoorMapCoordinate, floorOrdinal: Int, at time: Date) {
        guard actual.isValid, measured.isValid,
              RoutingGeometry.distanceMeters(from: measured, to: actual) <= Self.maximumOffsetMeters else { return nil }
        northMeters = (actual.latitude - measured.latitude) * Self.metersPerDegreeLatitude
        eastMeters = (actual.longitude - measured.longitude) * Self.metersPerDegreeLongitude(at: measured.latitude)
        measuredCoordinate = measured
        self.floorOrdinal = floorOrdinal
        anchoredAt = time
    }

    func isValid(at time: Date, floorOrdinal: Int?, near coordinate: IndoorMapCoordinate) -> Bool {
        let age = time.timeIntervalSince(anchoredAt)
        return floorOrdinal == self.floorOrdinal && (0...Self.lifetimeSeconds).contains(age)
            && RoutingGeometry.distanceMeters(from: measuredCoordinate, to: coordinate) <= Self.rangeMeters
    }

    func corrected(_ coordinate: IndoorMapCoordinate) -> IndoorMapCoordinate {
        .init(latitude: coordinate.latitude + northMeters / Self.metersPerDegreeLatitude,
              longitude: coordinate.longitude + eastMeters / Self.metersPerDegreeLongitude(at: coordinate.latitude))
    }

    private static let metersPerDegreeLatitude = 111_195.0
    private static func metersPerDegreeLongitude(at latitude: Double) -> Double {
        metersPerDegreeLatitude * cos(latitude * .pi / 180)
    }
}
