import ComposableArchitecture
import Foundation
import Testing
@testable import fingerprint_library

@MainActor
struct IndoorMapLocationFloorTests {
    private let now = Date(timeIntervalSinceReferenceDate: 1_000)

    private func position(inside: Bool, floor: Int, offset: Double = 0) -> IndoorPosition {
        .init(coordinate: inside ? .init(latitude: 36.0127633, longitude: 129.3251348)
            : .init(latitude: 36.0129766, longitude: 129.3257150),
            floorOrdinal: floor, horizontalAccuracy: 5, timestamp: now.addingTimeInterval(offset), source: .sensor)
    }

    private func store(_ state: IndoorMapFeature.State) -> TestStoreOf<IndoorMapFeature> {
        let store = TestStore(initialState: state) { IndoorMapFeature() } withDependencies: {
            $0.uuid = .incrementing
            $0.date.now = now
            $0.indoorShelfLabelClient.load = { _ in [] }
        }
        store.exhaustivity = .off
        return store
    }

    @Test(arguments: [false, true]) func 지도와_위치의_도착_순서와_관계없이_외부는_3층이다(locationFirst: Bool) async throws {
        let map = try await BundledIndoorMapLoader().loadLibrary()
        let store = store(withDependencies { $0.uuid = .incrementing } operation: { IndoorMapFeature.State() })
        if locationFirst { await store.send(.locationEvent(.position(position(inside: false, floor: 4)))) }
        await store.send(.mapLoaded(map))
        if !locationFirst { await store.send(.locationEvent(.position(position(inside: false, floor: 4)))) }
        #expect(store.state.selectedFloor?.ordinal == 2)
        #expect(store.state.positionFloorOrdinal == nil)
        #expect(!store.state.showsNativeUserLocation)
        await store.finish()
    }

    @Test func 사용자가_선택한_층은_외부와_내부_GPS_층보다_우선한다() async throws {
        let map = try await BundledIndoorMapLoader().loadLibrary()
        let store = store(withDependencies { $0.uuid = .incrementing } operation: { IndoorMapFeature.State() })
        await store.send(.mapLoaded(map))
        let selected = try #require(map.floors.first { $0.ordinal == 3 })
        await store.send(.floorSelected(selected.id))
        await store.send(.locationEvent(.position(position(inside: false, floor: 4))))
        await store.send(.locationEvent(.position(position(inside: true, floor: 2, offset: 1))))
        #expect(store.state.selectedFloorID == selected.id)
        await store.send(.mapLoaded(map))
        #expect(store.state.selectedFloorID == selected.id)
        await store.send(.locationEvent(.authorization(.authorized(precise: true))))
        await store.send(.currentLocationTapped)
        #expect(store.state.selectedFloor?.ordinal == 2)
        await store.finish()
    }

    @Test func 내부에서_밖으로_나오면_외부_층을_무시하고_3층으로_돌아간다() async throws {
        let map = try await BundledIndoorMapLoader().loadLibrary()
        let store = store(withDependencies { $0.uuid = .incrementing } operation: { IndoorMapFeature.State() })
        await store.send(.mapLoaded(map))
        await store.send(.locationEvent(.position(position(inside: true, floor: 3))))
        #expect(store.state.selectedFloor?.ordinal == 3)
        await store.send(.locationEvent(.position(position(inside: false, floor: 4, offset: 1))))
        #expect(store.state.selectedFloor?.ordinal == 2)
        await store.finish()
    }
}
