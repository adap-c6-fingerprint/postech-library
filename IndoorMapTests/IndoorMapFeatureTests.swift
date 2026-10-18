import ComposableArchitecture
import Foundation
import Testing
@testable import fingerprint_library

extension IndoorMapSerialTests {
    @MainActor
    struct IndoorMapFeatureTests {
        private actor PermissionProbe {
            var requests = 0
            func request() { requests += 1 }
        }

        private func readyState() -> IndoorMapFeature.State {
            var state = IndoorMapFeature.State()
            state.map = IndoorMapTestData.map()
            state.selectedFloorID = IndoorMapTestData.upperID
            state.isActive = true
            state.authorization = .authorized(precise: true)
            return state
        }

        @Test("비동기 로딩 결과를 지도와 최초 층에 반영한다")
        func loadMap() async {
            let map = IndoorMapTestData.map()
            let store = TestStore(initialState: IndoorMapFeature.State()) { IndoorMapFeature() } withDependencies: {
                $0.indoorMapClient.load = { map }
            }
            await store.send(.task) { $0.isLoading = true; $0.isActive = true }
            await store.receive(\.mapLoaded) {
                $0.isLoading = false
                $0.map = map
                $0.selectedFloorID = IndoorMapTestData.groundID
                $0.cameraRequest = .init(id: 1, target: .floor(IndoorMapTestData.groundID))
                $0.isLoadingNavigation = true
                $0.navigationRequestID = 1
            }
            await store.receive(\.navigationFailed) {
                $0.isLoadingNavigation = false
                $0.navigationLoadError = IndoorMapLoadError.missingResource("test routing").localizedDescription
            }
            await store.finish()
        }

        @Test("센서 수신과 지도 조회 층 변경이 수동 현재 위치를 덮어쓰지 않는다")
        func manualModeIsSticky() async {
            var initial = readyState()
            initial.latestPosition = IndoorMapTestData.position()
            let store = TestStore(initialState: initial) { IndoorMapFeature() } withDependencies: {
                $0.date.now = IndoorMapTestData.now
            }
            let manual = IndoorPosition(coordinate: IndoorMapTestData.point, floorOrdinal: 4, horizontalAccuracy: nil,
                                        timestamp: IndoorMapTestData.now, source: .manual)
            await store.send(.manualPointSelected(IndoorMapTestData.point)) {
                $0.manualPosition = manual
                $0.cameraRequest = .init(id: 1, target: .position(IndoorMapTestData.point))
            }
            let sensor = IndoorMapTestData.position(floor: 0)
            await store.send(.locationEvent(.position(sensor))) { $0.latestPosition = sensor }
            await store.send(.floorSelected(IndoorMapTestData.groundID)) {
                $0.selectedFloorID = IndoorMapTestData.groundID
                $0.cameraRequest = .init(id: 2, target: .floor(IndoorMapTestData.groundID))
            }
            #expect(store.state.currentPosition == manual)
            #expect(!store.state.showsNativeUserLocation)
            await store.send(.currentLocationTapped) {
                $0.manualPosition = nil
                $0.cameraRequest = .init(id: 3, target: .position(sensor.coordinate))
            }
            #expect(store.state.showsNativeUserLocation)
            #expect(store.state.currentPosition == sensor)
        }

        @Test("권한 거부 상태에서도 유효한 출발점을 지정하고 센서 모드로 복귀할 수 있다")
        func deniedPermissionFallback() async {
            var initial = readyState()
            initial.authorization = .denied
            let store = TestStore(initialState: initial) { IndoorMapFeature() } withDependencies: {
                $0.date.now = IndoorMapTestData.now
            }
            await store.send(.manualOriginTapped) {
                $0.isPlacingOrigin = true
                $0.locationMessage = "현재 층을 선택한 뒤 지도에서 출발점을 눌러주세요."
            }
            await store.send(.manualPointSelected(.init(latitude: 36.005, longitude: 129.005))) {
                $0.locationMessage = "선택한 층의 도면 안에서 출발점을 지정해주세요."
            }
            #expect(store.state.manualPosition == nil)
            await store.send(.manualPointSelected(IndoorMapTestData.point)) {
                $0.isPlacingOrigin = false
                $0.locationMessage = nil
                $0.manualPosition = .init(coordinate: IndoorMapTestData.point, floorOrdinal: 4, horizontalAccuracy: nil,
                                          timestamp: IndoorMapTestData.now, source: .manual)
                $0.cameraRequest = .init(id: 1, target: .position(IndoorMapTestData.point))
            }
            await store.send(.currentLocationTapped) {
                $0.manualPosition = nil
                $0.locationMessage = "위치 권한이 꺼져 있어요. 설정에서 위치 접근을 허용하거나 출발점을 직접 지정해주세요."
            }
        }

        @Test("오래된 위치와 순서가 뒤바뀐 샘플을 현재 위치에 반영하지 않는다")
        func staleAndOutOfOrderSamples() async {
            var initial = readyState()
            initial.latestPosition = IndoorMapTestData.position()
            let store = TestStore(initialState: initial) { IndoorMapFeature() } withDependencies: {
                $0.date.now = IndoorMapTestData.now
            }
            await store.send(.locationEvent(.position(IndoorMapTestData.position(age: 60))))
            await store.send(.locationEvent(.position(IndoorMapTestData.position(age: 1))))
            await store.send(.locationEvent(.position(IndoorMapTestData.position(age: -10))))
            await store.send(.locationEvent(.position(IndoorMapTestData.position(accuracy: -1))))
            await store.send(.floorSelected(IndoorMapTestData.groundID)) {
                $0.selectedFloorID = IndoorMapTestData.groundID
                $0.cameraRequest = .init(id: 1, target: .floor(IndoorMapTestData.groundID))
            }
            #expect(!store.state.showsNativeUserLocation)
            await store.send(.currentLocationTapped) {
                $0.selectedFloorID = IndoorMapTestData.upperID
                $0.cameraRequest = .init(id: 2, target: .position(IndoorMapTestData.point))
            }
        }

        @Test("위치 권한이 철회되면 센서 위치를 지우고 수동 위치는 보존한다")
        func revokedPermission() async {
            var initial = readyState()
            initial.latestPosition = IndoorMapTestData.position()
            initial.manualPosition = .init(coordinate: IndoorMapTestData.point, floorOrdinal: 4, horizontalAccuracy: nil,
                                           timestamp: IndoorMapTestData.now, source: .manual)
            let store = TestStore(initialState: initial) { IndoorMapFeature() }
            await store.send(.locationEvent(.authorization(.denied))) {
                $0.authorization = .denied
                $0.latestPosition = nil
            }
            #expect(store.state.manualPosition != nil)
            #expect(!store.state.showsNativeUserLocation)
        }

        @Test("센서 좌표가 없으면 층 지정 후 지도에서 출발점을 입력받는다")
        func manualFloorWithoutPosition() async {
            let store = TestStore(initialState: readyState()) { IndoorMapFeature() } withDependencies: {
                $0.date.now = IndoorMapTestData.now
            }
            await store.send(.manualFloorSelected(IndoorMapTestData.groundID)) {
                $0.selectedFloorID = IndoorMapTestData.groundID
                $0.isPlacingOrigin = true
                $0.locationMessage = "현재 위치를 지정할 수 없어요. 선택한 층의 도면에서 출발점을 눌러주세요."
                $0.cameraRequest = .init(id: 1, target: .floor(IndoorMapTestData.groundID))
            }
            #expect(store.state.manualPosition == nil)
        }

        @Test("뷰에서 나갈 때 장기 위치 스트림을 취소한다")
        func cancelsLocationStream() async {
            let (events, continuation) = AsyncStream.makeStream(of: IndoorLocationEvent.self)
            let map = IndoorMapTestData.map()
            let store = TestStore(initialState: IndoorMapFeature.State()) { IndoorMapFeature() } withDependencies: {
                $0.indoorMapClient.load = { map }
                $0.indoorLocationClient.events = { events }
            }
            await store.send(.task) { $0.isActive = true; $0.isLoading = true }
            await store.receive(\.mapLoaded) {
                $0.map = map
                $0.isLoading = false
                $0.selectedFloorID = IndoorMapTestData.groundID
                $0.cameraRequest = .init(id: 1, target: .floor(IndoorMapTestData.groundID))
                $0.isLoadingNavigation = true
                $0.navigationRequestID = 1
            }
            await store.receive(\.navigationFailed) {
                $0.isLoadingNavigation = false
                $0.navigationLoadError = IndoorMapLoadError.missingResource("test routing").localizedDescription
            }
            continuation.yield(.authorization(.denied))
            await store.receive(\.locationEvent) { $0.authorization = .denied }
            await store.send(.disappeared) { $0.isActive = false }
            await store.finish()
        }

        @Test("권한은 화면 진입이 아닌 현재 위치 버튼에서만 요청한다")
        func requestsPermissionOnUserAction() async {
            var initial = readyState()
            initial.authorization = .notDetermined
            let probe = PermissionProbe()
            let store = TestStore(initialState: initial) { IndoorMapFeature() } withDependencies: {
                $0.indoorLocationClient.requestPermission = { await probe.request() }
            }
            await store.send(.task) {
                $0.isLoadingNavigation = true
                $0.navigationRequestID = 1
            }
            await store.receive(\.navigationFailed) {
                $0.isLoadingNavigation = false
                $0.navigationLoadError = IndoorMapLoadError.missingResource("test routing").localizedDescription
            }
            await store.finish()
            #expect(await probe.requests == 0)
            let task = await store.send(.currentLocationTapped) { $0.wantsRecenter = true }
            await task.finish()
            #expect(await probe.requests == 1)
            // 권한 스트림의 초기 상태가 늦게 와도 사용자의 중심 이동 요청은 보존한다.
            await store.send(.locationEvent(.authorization(.notDetermined)))
            await store.send(.locationEvent(.authorization(.authorized(precise: false)))) {
                $0.authorization = .authorized(precise: false)
            }
            #expect(store.state.wantsRecenter)
        }

        @Test("현재 층을 지정할 때 오래된 센서 좌표를 수동 위치로 확정하지 않는다")
        func staleManualFloorFallback() async {
            var initial = readyState()
            initial.latestPosition = IndoorMapTestData.position(age: 60)
            let store = TestStore(initialState: initial) { IndoorMapFeature() } withDependencies: {
                $0.date.now = IndoorMapTestData.now
            }
            await store.send(.manualFloorSelected(IndoorMapTestData.groundID)) {
                $0.selectedFloorID = IndoorMapTestData.groundID
                $0.isPlacingOrigin = true
                $0.locationMessage = "현재 위치를 지정할 수 없어요. 선택한 층의 도면에서 출발점을 눌러주세요."
                $0.cameraRequest = .init(id: 1, target: .floor(IndoorMapTestData.groundID))
            }
            #expect(store.state.manualPosition == nil)
        }
    }
}
