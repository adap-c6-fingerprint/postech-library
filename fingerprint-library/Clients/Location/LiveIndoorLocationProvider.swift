import CoreLocation
import Foundation

/// CLLocationManager의 delegate를 Feature에서 취소할 수 있는 비동기 스트림으로 변환한다.
@MainActor
final class LiveIndoorLocationProvider: NSObject, CLLocationManagerDelegate {
    static let shared = LiveIndoorLocationProvider()
    private let manager = CLLocationManager()
    private var subscribers: [UUID: AsyncStream<IndoorLocationEvent>.Continuation] = [:]

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
        manager.activityType = .otherNavigation
    }

    func events() -> AsyncStream<IndoorLocationEvent> {
        let id = UUID()
        let (stream, continuation) = AsyncStream.makeStream(
            of: IndoorLocationEvent.self, bufferingPolicy: .bufferingNewest(10)
        )
        subscribers[id] = continuation
        continuation.yield(.authorization(authorization))
        continuation.onTermination = { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.subscribers.removeValue(forKey: id)
                if self.subscribers.isEmpty { self.manager.stopUpdatingLocation() }
            }
        }
        if authorization.isAuthorized { manager.startUpdatingLocation() }
        return stream
    }

    func requestPermission() {
        guard manager.authorizationStatus == .notDetermined else { return }
        manager.requestWhenInUseAuthorization()
    }

    private var authorization: IndoorLocationAuthorization {
        guard CLLocationManager.locationServicesEnabled() else { return .servicesDisabled }
        switch manager.authorizationStatus {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .restricted: return .restricted
        case .authorizedWhenInUse, .authorizedAlways:
            return .authorized(precise: manager.accuracyAuthorization == .fullAccuracy)
        @unknown default: return .restricted
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        publish(.authorization(authorization))
        if authorization.isAuthorized && !subscribers.isEmpty {
            manager.startUpdatingLocation()
        } else {
            manager.stopUpdatingLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        for location in locations {
            publish(.position(IndoorPosition(
                coordinate: IndoorMapCoordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude),
                floorOrdinal: location.floor?.level, horizontalAccuracy: location.horizontalAccuracy,
                timestamp: location.timestamp, source: .sensor
            )))
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        if (error as? CLError)?.code == .denied { publish(.authorization(authorization)) }
        else { publish(.unavailable("현재 위치를 확인할 수 없어요. 잠시 후 다시 시도하거나 출발점을 지정해주세요.")) }
    }

    private func publish(_ event: IndoorLocationEvent) {
        for continuation in subscribers.values { continuation.yield(event) }
    }
}
