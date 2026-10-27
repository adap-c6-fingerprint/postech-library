import ComposableArchitecture
import Foundation
import Testing
@testable import fingerprint_library

extension IndoorMapSerialTests {
    @MainActor
    struct IndoorShelfLabelFeatureTests {
        @Test("도착 노드가 준비되지 않아도 서가 레이블을 불러오고 지도·층·카메라를 유지한다")
        func loadsWithoutNavigation() async throws {
            let map = try await BundledIndoorMapLoader().loadLibrary()
            let labels = try await BundledShelfLabelLoader().loadLibrary(on: map)
            var initial = IndoorMapFeature.State()
            initial.map = map
            initial.selectedFloorID = map.floors[2].id
            initial.navigationLoadError = IndoorNavigationLoadError.notPrepared.localizedDescription
            initial.cameraRequest = .init(id: 1, target: .initialFloor(map.floors[0].id))
            let store = TestStore(initialState: initial) { IndoorMapFeature() } withDependencies: {
                $0.indoorShelfLabelClient = .init(supports: { _ in true }, load: { _ in labels })
            }
            await store.send(.retryShelfLabelsTapped) {
                $0.isLoadingShelfLabels = true
                $0.shelfLabelRequestID = 1
            }
            await store.receive(\.shelfLabelsLoaded) {
                $0.isLoadingShelfLabels = false
                $0.shelfLabels = labels
            }
            #expect(store.state.navigation == nil)
            #expect(store.state.navigationLoadError == initial.navigationLoadError)
            #expect(store.state.cameraRequest == initial.cameraRequest)
            #expect(store.state.selectedFloorID == initial.selectedFloorID)
            await store.finish()
        }

        @Test("서가 자료 실패는 지도를 유지하며 재시도할 수 있다")
        func retriesLabelsAfterFailure() async throws {
            let map = try await BundledIndoorMapLoader().loadLibrary()
            let labels = try await BundledShelfLabelLoader().loadLibrary(on: map)
            var initial = IndoorMapFeature.State()
            initial.map = map
            initial.selectedFloorID = map.floors[2].id
            let store = TestStore(initialState: initial) { IndoorMapFeature() } withDependencies: {
                $0.indoorShelfLabelClient = .init(supports: { _ in true }, load: { _ in throw ShelfLabelLoadError.missingResource })
            }
            await store.send(.retryShelfLabelsTapped) {
                $0.isLoadingShelfLabels = true
                $0.shelfLabelRequestID = 1
            }
            await store.receive(\.shelfLabelsFailed) {
                $0.isLoadingShelfLabels = false
                $0.shelfLabelError = ShelfLabelLoadError.missingResource.localizedDescription
            }
            #expect(store.state.map == map)
            store.dependencies.indoorShelfLabelClient.load = { _ in labels }
            await store.send(.retryShelfLabelsTapped) {
                $0.isLoadingShelfLabels = true
                $0.shelfLabelError = nil
                $0.shelfLabelRequestID = 2
            }
            await store.receive(\.shelfLabelsLoaded) {
                $0.isLoadingShelfLabels = false
                $0.shelfLabels = labels
            }
            await store.finish()
        }

        @Test("화면 종료 후 도착한 이전 서가 응답은 무시한다")
        func rejectsLateLabelsAfterDisappearance() async throws {
            let map = try await BundledIndoorMapLoader().loadLibrary()
            let labels = try await BundledShelfLabelLoader().loadLibrary(on: map)
            var initial = IndoorMapFeature.State()
            initial.map = map
            initial.isActive = true
            initial.isLoadingShelfLabels = true
            initial.shelfLabelRequestID = 1
            let store = TestStore(initialState: initial) { IndoorMapFeature() }
            await store.send(.disappeared) {
                $0.isActive = false
                $0.isLoadingShelfLabels = false
                $0.shelfLabelRequestID = 2
            }
            await store.send(.shelfLabelsLoaded(requestID: 1, labels))
            await store.send(.shelfLabelsFailed(requestID: 1, "늦은 오류"))
            #expect(store.state.shelfLabels.isEmpty)
            #expect(store.state.shelfLabelError == nil)
            await store.finish()
        }
    }
}
