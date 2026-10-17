import ComposableArchitecture
import Foundation
import Testing
@testable import fingerprint_library

@MainActor
struct IndoorNavigationFeatureTests {
    @Test("진행 중인 실제 navigation effect는 화면 이탈로 취소된다")
    func cancelsInFlightLoad() async throws {
        let root = try NavigationTestFixture.directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let (map, data) = try await NavigationTestFixture.load(root)
        let started = AsyncStream<Void>.makeStream()
        var initial = IndoorMapFeature.State()
        initial.map = map
        let store = TestStore(initialState: initial) { IndoorMapFeature() } withDependencies: {
            $0.indoorNavigationClient.load = { _ in
                started.continuation.yield(())
                try await Task.sleep(for: .seconds(5))
                return data
            }
        }
        await store.send(.task) {
            $0.isActive = true
            $0.isLoadingNavigation = true
            $0.navigationRequestID = 1
        }
        var iterator = started.stream.makeAsyncIterator()
        _ = await iterator.next()
        await store.send(.disappeared) {
            $0.isActive = false
            $0.isLoadingNavigation = false
            $0.navigationRequestID = 2
        }
        await store.finish()
        #expect(store.state.navigation == nil)
    }

    @Test("routing 로딩 실패에도 지도를 유지하며 명시적으로 재시도한다")
    func keepsMapAndRetries() async throws {
        let root = try NavigationTestFixture.directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let (map, data) = try await NavigationTestFixture.load(root)
        var initial = IndoorMapFeature.State()
        initial.map = map
        initial.isActive = true
        initial.isLoadingNavigation = true
        initial.navigationRequestID = 1
        let store = TestStore(initialState: initial) { IndoorMapFeature() } withDependencies: {
            $0.indoorNavigationClient.load = { _ in data }
        }
        await store.send(.navigationFailed(requestID: 1, "불일치")) {
            $0.isLoadingNavigation = false
            $0.navigationLoadError = "불일치"
        }
        #expect(store.state.map == map)
        #expect(store.state.navigation == nil)
        await store.send(.retryNavigationTapped) {
            $0.navigationLoadError = nil
            $0.isLoadingNavigation = true
            $0.navigationRequestID = 2
        }
        await store.receive(\.navigationLoaded) {
            $0.isLoadingNavigation = false
            $0.navigation = data
        }
        await store.finish()
        #expect(try store.state.navigation?.shelves.destination(for: .init(datasetID: "test-demo", value: "mock-01")).arrivalNodeID == "b")
    }

    @Test("화면 이탈 시 로딩을 취소하고 늦은 결과를 무시하며 재진입에서 다시 읽는다")
    func invalidatesOldResponses() async throws {
        let root = try NavigationTestFixture.directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let (map, data) = try await NavigationTestFixture.load(root)
        var initial = IndoorMapFeature.State()
        initial.map = map
        initial.isActive = true
        initial.isLoadingNavigation = true
        initial.navigationRequestID = 3
        let store = TestStore(initialState: initial) { IndoorMapFeature() } withDependencies: {
            $0.indoorNavigationClient.load = { _ in data }
        }
        await store.send(.disappeared) {
            $0.isActive = false
            $0.isLoadingNavigation = false
            $0.navigationRequestID = 4
        }
        await store.send(.navigationLoaded(requestID: 3, data))
        await store.send(.navigationFailed(requestID: 3, "과거 오류"))
        await store.send(.task) {
            $0.isActive = true
            $0.isLoadingNavigation = true
            $0.navigationRequestID = 5
        }
        await store.receive(\.navigationLoaded) {
            $0.isLoadingNavigation = false
            $0.navigation = data
        }
        await store.finish()
    }
}
