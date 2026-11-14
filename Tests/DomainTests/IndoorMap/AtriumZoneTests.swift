import Foundation
import Testing
@testable import fingerprint_library

struct AtriumZoneTests {
    @Test func 번들_중앙_공간_세_윤곽의_거리와_신뢰도를_확인한다() async throws {
        let map = try await BundledIndoorMapLoader().loadLibrary()
        let zone = AtriumZone(map: map)
        #expect(zone.outlines.count == 3)
        let inside = IndoorMapCoordinate(latitude: 36.0128124, longitude: 129.3250992)
        let near = IndoorMapCoordinate(latitude: 36.0127969, longitude: 129.3250591)
        let far = IndoorMapCoordinate(latitude: 36.0127815, longitude: 129.3250190)
        #expect(zone.trust(at: inside) == 0.1)
        #expect(zone.trust(at: near) == 0.1)
        #expect(zone.trust(at: far) == 1)
        #expect(zone.trust(at: .init(latitude: 36, longitude: 129)) == 1)
        #expect(zone.distanceMeters(at: inside) == 0)
        #expect(abs(try #require(zone.distanceMeters(at: near)) - 1) < 0.05)
        #expect(abs(try #require(zone.distanceMeters(at: far)) - 3.4) < 0.05)
        let invalid = IndoorMapCoordinate(latitude: .nan, longitude: 129)
        #expect(zone.trust(at: invalid) == 0.1)
        #expect(zone.distanceMeters(at: invalid) == nil)
    }

    @Test func 윤곽을_읽지_못하면_가중치_없이_동작한다() {
        let zone = AtriumZone(outlines: [])
        #expect(zone.trust(at: .init(latitude: 36, longitude: 129)) == 1)
        #expect(zone.distanceMeters(at: .init(latitude: 36, longitude: 129)) == nil)
    }
}
