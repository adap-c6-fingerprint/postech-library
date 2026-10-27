import ComposableArchitecture
import Foundation
import Testing
@testable import fingerprint_library

extension IndoorMapSerialTests {
    @MainActor
    struct IndoorSimulationFeatureTests {
        private func position(floor: Int = 4, latitude: Double = IndoorMapTestData.point.latitude) -> IndoorPosition {
            .init(coordinate: .init(latitude: latitude, longitude: IndoorMapTestData.point.longitude),
                  floorOrdinal: floor, horizontalAccuracy: 0, timestamp: IndoorMapTestData.now, source: .simulation)
        }

        @Test("시뮬레이터의 초기 층·층 이동을 반영하고 같은 층의 수신으로 지도 조회를 되돌리지 않는다")
        func followsSimulationFloorChanges() async {
            var initial = IndoorMapFeature.State()
            initial.map = IndoorMapTestData.map()
            initial.selectedFloorID = IndoorMapTestData.groundID
            initial.isActive = true
            initial.authorization = .authorized(precise: true)
            let store = TestStore(initialState: initial) { IndoorMapFeature() } withDependencies: {
                $0.date.now = IndoorMapTestData.now
            }
            let upper = position()
            await store.send(.locationEvent(.position(upper))) {
                $0.latestPosition = upper
                $0.selectedFloorID = IndoorMapTestData.upperID
                $0.cameraRequest = .init(id: 1, target: .floor(IndoorMapTestData.upperID))
            }
            #expect(!store.state.showsNativeUserLocation)
            await store.send(.floorSelected(IndoorMapTestData.groundID)) {
                $0.selectedFloorID = IndoorMapTestData.groundID
                $0.cameraRequest = .init(id: 2, target: .floor(IndoorMapTestData.groundID))
            }
            await store.send(.locationEvent(.position(upper)))
            #expect(store.state.currentPosition?.floorOrdinal == 4)
            #expect(store.state.selectedFloorID == IndoorMapTestData.groundID)
            let lower = position(floor: 0)
            await store.send(.locationEvent(.position(lower))) { $0.latestPosition = lower }
            await store.send(.locationEvent(.position(upper))) {
                $0.latestPosition = upper
                $0.selectedFloorID = IndoorMapTestData.upperID
                $0.cameraRequest = .init(id: 3, target: .floor(IndoorMapTestData.upperID))
            }
        }

        @Test("알 수 없는 층·도면 바깥 위치와 연결 단절을 현재 출발점으로 유지하지 않는다")
        func invalidatesUnavailablePosition() async {
            var initial = IndoorMapFeature.State()
            initial.map = IndoorMapTestData.map()
            initial.selectedFloorID = IndoorMapTestData.upperID
            initial.latestPosition = position()
            let store = TestStore(initialState: initial) { IndoorMapFeature() } withDependencies: {
                $0.date.now = IndoorMapTestData.now
            }
            let mismatch = "시뮬레이터에서 앱과 같은 도면과 층을 선택해주세요."
            let olderMismatch = IndoorPosition(coordinate: .init(latitude: 37, longitude: 129),
                floorOrdinal: 99, horizontalAccuracy: 0,
                timestamp: IndoorMapTestData.now.addingTimeInterval(-1), source: .simulation)
            await store.send(.locationEvent(.position(olderMismatch)))
            await store.send(.locationEvent(.position(position(floor: 99)))) {
                $0.latestPosition = nil
                $0.locationMessage = mismatch
            }
            await store.send(.locationEvent(.position(position(latitude: 37))))
            let valid = position()
            await store.send(.locationEvent(.position(valid))) {
                $0.latestPosition = valid
                $0.locationMessage = nil
            }
            await store.send(.locationEvent(.unavailable("연결 단절"))) {
                $0.latestPosition = nil
                $0.locationMessage = "연결 단절"
            }
            #expect(store.state.currentPosition == nil)
        }

        @Test("현재 층의 등록된 가상 서가만 선택하고 층을 바꾸면 선택을 해제한다")
        func selectsMappedShelf() async throws {
            let root = try NavigationTestFixture.directory()
            defer { try? FileManager.default.removeItem(at: root) }
            let (map, navigation) = try await NavigationTestFixture.load(root)
            var initial = IndoorMapFeature.State()
            initial.map = map
            initial.selectedFloorID = map.floors.first?.id
            initial.navigation = navigation
            let store = TestStore(initialState: initial) { IndoorMapFeature() }
            let shelf = try #require(navigation.shelves.destinations.first)
            #expect(store.state.mockShelves == [shelf])
            await store.send(.shelfSelected(shelf.key)) { $0.selectedShelfKey = shelf.key }
            #expect(try navigation.shelves.destination(for: shelf.key).arrivalNodeID == "b")
            await store.send(.shelfSelected(.init(datasetID: "wrong-dataset", value: shelf.key.value))) {
                $0.selectedShelfKey = nil
            }
            await store.send(.shelfSelected(shelf.key)) { $0.selectedShelfKey = shelf.key }
            await store.send(.floorSelected(shelf.floorID)) {
                $0.selectedShelfKey = nil
                $0.cameraRequest = .init(id: 1, target: .floor(shelf.floorID))
            }
        }
    }
}
