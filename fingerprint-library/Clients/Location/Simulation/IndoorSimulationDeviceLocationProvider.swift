#if DEBUG
import CoreLocation
import Foundation

/// Mac의 좌표·층과 실기기 나침반만 합친다. 기기의 GPS·층은 QA 위치를 덮지 않는다.
@MainActor
enum IndoorSimulationDeviceLocationProvider {
    static func events() -> AsyncStream<IndoorLocationEvent> {
        AsyncStream(bufferingPolicy: .bufferingNewest(10)) { continuation in
            let merger = PositionMerger(continuation: continuation)
            let task = Task {
                await withTaskGroup(of: Void.self) { group in
                    group.addTask {
                        for await event in IndoorSimulationLocationProvider.events() {
                            guard !Task.isCancelled else { return }
                            await merger.receive(event)
                        }
                    }
                    group.addTask {
                        for await heading in await DeviceHeadingProvider.shared.events() {
                            guard !Task.isCancelled else { return }
                            await merger.receive(heading)
                        }
                    }
                    await group.waitForAll()
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private final class PositionMerger {
        let continuation: AsyncStream<IndoorLocationEvent>.Continuation
        var position: IndoorPosition?
        var heading: DeviceHeadingProvider.Sample?

        init(continuation: AsyncStream<IndoorLocationEvent>.Continuation) {
            self.continuation = continuation
        }

        func receive(_ event: IndoorLocationEvent) {
            switch event {
            case let .position(position):
                self.position = position
                publishPosition()
            case .temporarilyUnavailable, .unavailable:
                position = nil
                continuation.yield(event)
            case .authorization:
                continuation.yield(event)
            }
        }

        func receive(_ heading: DeviceHeadingProvider.Sample?) {
            self.heading = heading
            publishPosition()
        }

        private func publishPosition() {
            let now = Date()
            guard let position, position.isRecent(at: now) else { return }
            let degrees = heading.flatMap {
                (-5...10).contains(now.timeIntervalSince($0.timestamp)) ? $0.degrees : nil
            }
            // 나침반 이벤트로 좌표 측정 시각을 연장하거나 마지막 위치를 되살리지 않는다.
            continuation.yield(.position(position.replacingHeading(degrees)))
        }
    }
}

/// Debug QA 연결 수명에만 나침반을 구독한다. 위치·층 업데이트는 시작하지 않는다.
@MainActor
private final class DeviceHeadingProvider: NSObject, CLLocationManagerDelegate {
    struct Sample: Sendable {
        let degrees: Double
        let timestamp: Date
    }

    static let shared = DeviceHeadingProvider()
    private let manager = CLLocationManager()
    private var subscribers: [UUID: AsyncStream<Sample?>.Continuation] = [:]
    private var latest: Sample?

    override init() {
        super.init()
        manager.delegate = self
        manager.headingFilter = kCLHeadingFilterNone
    }

    func events() -> AsyncStream<Sample?> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<Sample?>.makeStream(bufferingPolicy: .bufferingNewest(1))
        subscribers[id] = continuation
        continuation.yield(latest)
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.subscribers.removeValue(forKey: id)
                if self.subscribers.isEmpty {
                    self.manager.stopUpdatingHeading()
                    self.latest = nil
                }
            }
        }
        updateSubscription()
        return stream
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        updateSubscription()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading heading: CLHeading) {
        // Heading-only CoreLocation에는 trueHeading이 없을 수 있으므로 기기의 자북을 사용한다.
        let degrees = heading.trueHeading >= 0 ? heading.trueHeading : heading.magneticHeading
        guard heading.headingAccuracy.isFinite, heading.headingAccuracy >= 0,
              degrees.isFinite, (0..<360).contains(degrees) else {
            publish(nil)
            return
        }
        publish(Sample(degrees: degrees, timestamp: heading.timestamp))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        publish(nil)
    }

    private func updateSubscription() {
        guard !subscribers.isEmpty, CLLocationManager.headingAvailable(),
              manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways
        else {
            manager.stopUpdatingHeading()
            publish(nil)
            return
        }
        manager.startUpdatingHeading()
    }

    private func publish(_ sample: Sample?) {
        latest = sample
        for continuation in subscribers.values { continuation.yield(sample) }
    }
}
#endif
