import Foundation
import Testing
@testable import fingerprint_library

struct IndoorLocationSnapshotTests {
    func position(at seconds: TimeInterval, floor: Int? = 2) -> IndoorPosition {
        IndoorPosition(
            coordinate: .init(latitude: 36, longitude: 129), floorOrdinal: floor, horizontalAccuracy: 3,
            timestamp: Date(timeIntervalSinceReferenceDate: seconds), source: .sensor
        )
    }

    @Test func 처음_받는_쪽에는_현재_상태를_모두_알린다() {
        var snapshot = IndoorLocationSnapshot()
        snapshot.apply(.authorization(.authorized(precise: true)))
        snapshot.apply(.position(position(at: 10)))
        #expect(snapshot.events(since: nil) == [
            .authorization(.authorized(precise: true)), .position(position(at: 10))
        ])
    }

    @Test func 바뀐_부분만_알린다() {
        var previous = IndoorLocationSnapshot()
        previous.apply(.authorization(.authorized(precise: true)))
        previous.apply(.position(position(at: 10)))
        var current = previous
        current.apply(.position(position(at: 11)))
        #expect(current.events(since: previous) == [.position(position(at: 11))])
    }

    @Test func 늦게_온_위치는_최신_위치를_덮지_않는다() {
        var snapshot = IndoorLocationSnapshot()
        snapshot.apply(.position(position(at: 20)))
        snapshot.apply(.position(position(at: 15)))
        #expect(snapshot.position == position(at: 20))
    }

    @Test func 권한을_잃거나_수신이_끊기면_위치를_지운다() {
        var snapshot = IndoorLocationSnapshot()
        snapshot.apply(.position(position(at: 10)))
        snapshot.apply(.unavailable("끊김"))
        #expect(snapshot.position == nil)
        #expect(snapshot.availability == .unavailable("끊김"))

        snapshot.apply(.position(position(at: 11)))
        snapshot.apply(.authorization(.denied))
        #expect(snapshot.position == nil)
    }
}
