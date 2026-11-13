import CoreLocation
import Foundation

@MainActor
final class LiveIndoorLocationProvider: NSObject, CLLocationManagerDelegate {
    static let shared = LiveIndoorLocationProvider()
    private let manager: CLLocationManager
    private var lastLocation: CLLocation?
    private var lastHeading: CLHeading?
    private var subscribers: [UUID: AsyncStream<IndoorLocationEvent>.Continuation] = [:]
    private lazy var authorizationMonitor = IndoorLocationAuthorizationMonitor { [weak self] value in
        guard let self else { return }
        self.publish(.authorization(value))
        if value.isAuthorized && !self.subscribers.isEmpty {
            self.startUpdates()
        } else {
            self.stopUpdates()
        }
    }

    init(manager: CLLocationManager = CLLocationManager()) {
        self.manager = manager
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
        let authorization = authorizationMonitor.authorization
        continuation.yield(.authorization(authorization))
        continuation.onTermination = { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.subscribers.removeValue(forKey: id)
                if self.subscribers.isEmpty { self.stopUpdates() }
            }
        }
        if authorization.isAuthorized { startUpdates() }
        return stream
    }

    func requestPermission() {
        guard manager.authorizationStatus == .notDetermined else { return }
        manager.requestWhenInUseAuthorization()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationMonitor.update(status: manager.authorizationStatus,
                                    precise: manager.accuracyAuthorization == .fullAccuracy)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        for location in locations {
            if lastLocation.map({ location.timestamp >= $0.timestamp }) ?? true { lastLocation = location }
            publish(.position(position(from: location)))
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        lastHeading = newHeading
        publishHeadingChange()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        if (error as? CLError)?.code == .headingFailure {
            lastHeading = nil
            publishHeadingChange()
            return
        }
        lastLocation = nil
        let event = Self.failureEvent(for: error)
        if case .authorization(.denied) = event {
            authorizationMonitor.update(status: .denied, precise: false)
        }
        else { publish(event) }
    }

    private func startUpdates() {
        manager.startUpdatingLocation()
        if CLLocationManager.headingAvailable() { manager.startUpdatingHeading() }
    }

    private func stopUpdates() {
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
        lastLocation = nil
        lastHeading = nil
    }

    private func publishHeadingChange() {
        guard let lastLocation else { return }
        let position = position(from: lastLocation)
        guard position.isRecent(at: Date()) else { return }
        publish(.position(position))
    }

    private func position(from location: CLLocation) -> IndoorPosition {
        let heading: Double?
        if let lastHeading, lastHeading.headingAccuracy.isFinite, lastHeading.headingAccuracy >= 0,
           (-5...10).contains(Date().timeIntervalSince(lastHeading.timestamp)),
           lastHeading.trueHeading >= 0 {
            heading = lastHeading.trueHeading
        } else {
            heading = nil
        }
        return IndoorPosition(
            coordinate: .init(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude),
            floorOrdinal: location.floor?.level, horizontalAccuracy: location.horizontalAccuracy,
            timestamp: location.timestamp, source: .sensor, headingDegrees: heading
        )
    }

    nonisolated static func failureEvent(for error: any Error) -> IndoorLocationEvent {
        switch (error as? CLError)?.code {
        case .denied: .authorization(.denied)
        case .locationUnknown:
            .temporarilyUnavailable("위치 신호를 다시 확인하고 있어요. 표시된 경로는 계산 당시 출발 위치 기준이에요.")
        default: .unavailable("현재 위치를 확인할 수 없어요. 잠시 후 다시 시도해주세요.")
        }
    }

    private func publish(_ event: IndoorLocationEvent) {
        for continuation in subscribers.values { continuation.yield(event) }
    }
}
