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
