import CoreLocation
import Foundation
import Testing
@testable import fingerprint_library

struct IndoorLocationClientTests {
    @Test("재생 위치는 실제 센서 위치로 표시하지 않는다")
    func replaySource() async {
        let original = IndoorPosition(coordinate: IndoorMapTestData.point, floorOrdinal: 4, horizontalAccuracy: 3,
                                      timestamp: IndoorMapTestData.now, source: .sensor, headingDegrees: 315)
        let client = IndoorLocationClient.replaying([original], interval: .zero)
        var received: [IndoorLocationEvent] = []
        for await event in await client.events() { received.append(event) }
        #expect(received.count == 2)
        #expect(received.first == .authorization(.authorized(precise: true)))
        guard case .position(let position) = received.last else {
            Issue.record("재생 위치가 없습니다.")
            return
        }
        #expect(position.source == .replay)
        #expect(position.coordinate == IndoorMapTestData.point)
        #expect(position.floorOrdinal == 4)
        #expect(position.headingDegrees == 315)
    }
}

extension IndoorMapSerialTests {
    @MainActor
    struct LiveIndoorLocationProviderTests {
        @Test("위치 오류 후 방향만 갱신해도 이전 좌표를 복구하지 않고 새 위치부터 전달한다",
              arguments: [CLError.Code.locationUnknown, .network])
        func waitsForNewLocationAfterFailure(_ code: CLError.Code) async {
            let manager = TestLocationManager()
            let provider = LiveIndoorLocationProvider(manager: manager)
            var events = provider.events().makeAsyncIterator()
            _ = await events.next()
            let first = location(latitude: 36.001)
            let recovered = location(latitude: 36.002)

            provider.locationManager(manager, didUpdateLocations: [first])
            provider.locationManager(manager, didFailWithError: NSError(domain: kCLErrorDomain, code: code.rawValue))
            provider.locationManager(manager, didUpdateHeading: TestHeading(trueHeading: 90))
            provider.locationManager(manager, didUpdateLocations: [recovered])
            provider.locationManager(manager, didUpdateHeading: TestHeading(trueHeading: 180))

            guard case .position = await events.next() else {
                Issue.record("최초 위치가 없습니다.")
                return
            }
            #expect(await events.next() == LiveIndoorLocationProvider.failureEvent(
                for: NSError(domain: kCLErrorDomain, code: code.rawValue)
            ))
            guard case .position(let next) = await events.next(),
                  case .position(let rotated) = await events.next() else {
                Issue.record("새 위치와 방향 변경 이벤트가 없습니다.")
                return
            }
            #expect(next.coordinate.latitude == recovered.coordinate.latitude)
            #expect(next.headingDegrees == 90)
            #expect(rotated.coordinate == next.coordinate)
            #expect(rotated.headingDegrees == 180)
            #expect(rotated.timestamp == recovered.timestamp)
        }

        @Test("유효한 진북 방향만 지도에 전달하고 자기 방향으로 대체하지 않는다",
              arguments: [-1.0, 0, 90])
        func usesTrueNorthOnly(_ trueHeading: Double) async {
            let manager = TestLocationManager()
            let provider = LiveIndoorLocationProvider(manager: manager)
            var events = provider.events().makeAsyncIterator()
            _ = await events.next()
            let sample = location(latitude: 36.001)
            provider.locationManager(manager, didUpdateLocations: [sample])
            provider.locationManager(manager, didUpdateHeading: TestHeading(trueHeading: trueHeading))
            _ = await events.next()
            guard case .position(let position) = await events.next() else {
                Issue.record("방향 변경 이벤트가 없습니다.")
                return
            }
            #expect(position.headingDegrees == (trueHeading >= 0 ? trueHeading : nil))
            #expect(position.coordinate.latitude == sample.coordinate.latitude)
            #expect(position.timestamp == sample.timestamp)
        }

        @Test("방향 센서만 실패하면 위치는 유지하고 방향만 숨긴다")
        func preservesLocationAfterHeadingFailure() async {
            let manager = TestLocationManager()
            let provider = LiveIndoorLocationProvider(manager: manager)
            var events = provider.events().makeAsyncIterator()
            _ = await events.next()
            let sample = location(latitude: 36.001)
            provider.locationManager(manager, didUpdateLocations: [sample])
            provider.locationManager(manager, didUpdateHeading: TestHeading(trueHeading: 90))
            provider.locationManager(manager, didFailWithError: NSError(domain: kCLErrorDomain, code: CLError.Code.headingFailure.rawValue))
            _ = await events.next()
            _ = await events.next()
            guard case .position(let position) = await events.next() else {
                Issue.record("방향 실패 후 위치가 없습니다.")
                return
            }
            #expect(position.coordinate.latitude == sample.coordinate.latitude)
            #expect(position.headingDegrees == nil)
            #expect(position.timestamp == sample.timestamp)
        }

        private func location(latitude: Double) -> CLLocation {
            CLLocation(coordinate: .init(latitude: latitude, longitude: 129.001),
                       altitude: 0, horizontalAccuracy: 3, verticalAccuracy: 3, timestamp: Date())
        }
    }
}

/// 테스트가 실제 센서·권한 콜백을 받지 않도록 delegate 등록을 막는다.
nonisolated private final class TestLocationManager: CLLocationManager {
    override var delegate: (any CLLocationManagerDelegate)? {
        get { nil }
        set {}
    }
}

nonisolated private final class TestHeading: CLHeading {
    private let value: Double
    private let sampledAt = Date()

    init(trueHeading: Double) {
        value = trueHeading
        super.init()
    }

    required init?(coder: NSCoder) { fatalError("이 테스트는 디코딩하지 않습니다.") }

    override var trueHeading: CLLocationDirection { value }
    override var magneticHeading: CLLocationDirection { 75 }
    override var headingAccuracy: CLLocationDirection { 1 }
    override var timestamp: Date { sampledAt }
}
