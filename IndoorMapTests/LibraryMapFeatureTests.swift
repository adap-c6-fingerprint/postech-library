import ComposableArchitecture
import Foundation
import Testing
@testable import fingerprint_library

extension IndoorMapSerialTests {
    @MainActor
    struct LibraryMapFeatureTests {
        @Test("도서관 지도 첫 표시와 층 선택은 길찾기 자료 준비 전에도 유지된다")
        func keepsLibraryAvailableWithoutRouting() async throws {
            let map = try await BundledIndoorMapLoader().loadLibrary()
            let first = try #require(map.floors.first)
            let third = try #require(map.floors.first { $0.name == "3층" })
            var initial = IndoorMapFeature.State()
            initial.isLoading = true
            let store = TestStore(initialState: initial) { IndoorMapFeature() } withDependencies: {
                $0.indoorNavigationClient = .liveValue
            }
            await store.send(.mapLoaded(map)) {
                $0.isLoading = false
                $0.map = map
                $0.selectedFloorID = first.id
                $0.cameraRequest = .init(id: 1, target: .initialFloor(first.id))
                $0.isLoadingNavigation = true
                $0.navigationRequestID = 1
            }
            await store.receive(\.navigationFailed) {
                $0.isLoadingNavigation = false
                $0.navigationLoadError = IndoorNavigationLoadError.notPrepared.localizedDescription
            }
            await store.send(.floorSelected(third.id)) {
                $0.selectedFloorID = third.id
            }
            #expect(store.state.cameraRequest == .init(id: 1, target: .initialFloor(first.id)))
            #expect(store.state.map == map)
            #expect(store.state.selectedFloor?.name == "3층")
            #expect(store.state.navigation == nil)
            #expect(store.state.mockShelves.isEmpty)
            #expect(store.state.loadError == nil)
            await store.finish()
        }
    }
}
