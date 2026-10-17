import Foundation
import Testing
@testable import fingerprint_library

struct IndoorPositionTests {
    @Test("외곽 경계와 내부 ring을 구분한다")
    func polygonContainment() {
        let geometry = IndoorMapGeometry.polygon([IndoorMapTestData.square, IndoorMapTestData.hole])
        #expect(geometry.contains(IndoorMapTestData.point))
        #expect(geometry.contains(.init(latitude: 36, longitude: 129.001)))
        #expect(!geometry.contains(.init(latitude: 36.005, longitude: 129.005)))
        #expect(!geometry.contains(.init(latitude: 36.004, longitude: 129.005)))
        #expect(!geometry.contains(.init(latitude: 35.99, longitude: 129)))
        #expect(!IndoorMapGeometry.lineString(IndoorMapTestData.square).contains(IndoorMapTestData.point))
    }

    @Test("분리된 MultiPolygon의 어느 도형 안에 있어도 포함한다")
    func multiPolygonContainment() {
        let second = IndoorMapTestData.square.map { IndoorMapCoordinate(latitude: $0.latitude + 0.02, longitude: $0.longitude) }
        let geometry = IndoorMapGeometry.multiPolygon([[IndoorMapTestData.square, IndoorMapTestData.hole], [second]])
        #expect(geometry.contains(.init(latitude: 36.021, longitude: 129.001)))
        #expect(!geometry.contains(.init(latitude: 36.015, longitude: 129.001)))
        #expect(!geometry.contains(.init(latitude: 36.005, longitude: 129.005)))
    }

    @Test("오래되거나 미래이거나 정확도가 유효하지 않은 센서 위치를 거부한다")
    func invalidSamples() {
        let now = IndoorMapTestData.now
        #expect(IndoorMapTestData.position().isRecent(at: now))
        #expect(!IndoorMapTestData.position(age: 31).isRecent(at: now))
        #expect(!IndoorMapTestData.position(age: -6).isRecent(at: now))
        #expect(!IndoorMapTestData.position(accuracy: -1).isRecent(at: now))
        #expect(!IndoorMapTestData.position(accuracy: .nan).isRecent(at: now))
        #expect(IndoorMapTestData.position(accuracy: 100).isRecent(at: now))
        let manual = IndoorPosition(coordinate: IndoorMapTestData.point, floorOrdinal: 4, horizontalAccuracy: nil,
                                    timestamp: now.addingTimeInterval(-3_600), source: .manual)
        #expect(manual.isRecent(at: now))
        let invalid = IndoorPosition(coordinate: .init(latitude: 91, longitude: 129), floorOrdinal: nil,
                                     horizontalAccuracy: 3, timestamp: now, source: .sensor)
        #expect(!invalid.isRecent(at: now))
    }
}
