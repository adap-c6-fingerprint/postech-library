import CoreMotion
import Foundation

@MainActor
final class LiveBarometerProvider {
    static let shared = LiveBarometerProvider()

    private let altimeter = CMAltimeter()
    private var subscribers: [UUID: AsyncStream<BarometerSample>.Continuation] = [:]
    private var sessionID: UUID?

    func samples() -> AsyncStream<BarometerSample> {
        guard CMAltimeter.isRelativeAltitudeAvailable() else {
            return AsyncStream { $0.finish() }
        }
        switch CMAltimeter.authorizationStatus() {
        case .denied, .restricted:
            return AsyncStream { $0.finish() }
        case .notDetermined, .authorized:
            break
        @unknown default:
            return AsyncStream { $0.finish() }
        }

        let id = UUID()
        let (stream, continuation) = AsyncStream.makeStream(
            of: BarometerSample.self, bufferingPolicy: .bufferingNewest(1)
        )
        subscribers[id] = continuation
        continuation.onTermination = { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.subscribers.removeValue(forKey: id)
                if self.subscribers.isEmpty { self.stopUpdates() }
            }
        }
        if sessionID == nil { startUpdates() }
        return stream
    }

    private func startUpdates() {
        let id = UUID()
        sessionID = id
        // 위치 권한을 얻은 후에만 호출한다. 미결정이면 시스템이 동작 및 피트니스 권한을 묻는다.
        altimeter.startRelativeAltitudeUpdates(to: .main) { [weak self] data, error in
            let sample = data.map { BarometerSample(kilopascals: $0.pressure.doubleValue, timestamp: Date()) }
            let didFail = error != nil
            Task { @MainActor in
                guard let self, self.sessionID == id else { return }
                if didFail {
                    self.finishSubscribers()
                } else if let sample {
                    // 센서 주기와 무관한 표본 간격 제한은 순수 추정기에서 처리한다.
                    for continuation in self.subscribers.values { continuation.yield(sample) }
                }
            }
        }
    }

    private func finishSubscribers() {
        let continuations = Array(subscribers.values)
        subscribers.removeAll()
        stopUpdates()
        for continuation in continuations { continuation.finish() }
    }

    private func stopUpdates() {
        guard sessionID != nil else { return }
        sessionID = nil
        // 오류로 종료한 경우에도 start/stop 호출을 짝지어야 한다.
        altimeter.stopRelativeAltitudeUpdates()
    }
}
