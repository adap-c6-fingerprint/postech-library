import ComposableArchitecture
import Foundation
import Testing
@testable import fingerprint_library

extension IndoorMapSerialTests {
    @MainActor
    struct BookRoutePreviewFeatureTests {
        @Test("확정된 도서·서가를 Client에 전달하고 계산한 세션을 그대로 안내 입력으로 보존한다")
        func loadsRoute() async throws {
            let session = try NavigationGuidanceTestFixture.session()
            let state = readyState(session)
            let request = state.routeRequest
            let store = TestStore(initialState: state) { BookRoutePreviewFeature() } withDependencies: {
                $0.bookRoutePreviewClient.load = { map, labels, stops in
                    await MainActor.run {
                        #expect(map == session.map && labels == session.shelfLabels && stops == session.stops)
                    }
                    return session
                }
            }
            await store.send(.routeRequestChanged(request)) {
                $0.routeRequestID = 1
                $0.isLoadingRoute = true
            }
            await store.receive(\.routeLoaded) {
                $0.previewSession = session
                $0.isLoadingRoute = false
            }
            #expect(store.state.readySession == session)
            #expect(store.state.orderedBooks == session.stops.map(\.book))
            await store.finish()
        }

        @Test("미확정 입력은 계산하지 않고 오류·이전 요청의 늦은 결과를 현재 경로로 표시하지 않는다")
        func rejectsStaleResponses() async throws {
            let session = try NavigationGuidanceTestFixture.session()
            let state = readyState(session)
            let request = state.routeRequest
            let store = TestStore(initialState: BookRoutePreviewFeature.State()) { BookRoutePreviewFeature() }
            await store.send(.routeRequestChanged(.waiting)) { $0.routeRequestID = 1 }
            await store.send(.routeRequestChanged(request))
            await store.send(.routeLoaded(requestID: 0, request: request, session))
            await store.send(.routeFailed(requestID: 0, request: request, "늦은 오류"))
            #expect(store.state.previewSession == nil && store.state.routeError == nil)
        }

        @Test("경로 계산 실패를 표시하고 이전 경로와 층 선택은 지운다")
        func reportsFailure() async throws {
            let session = try NavigationGuidanceTestFixture.session()
            var state = readyState(session)
            state.previewSession = session
            state.routeFloorID = session.origin.floorID
            let request = state.routeRequest
            let store = TestStore(initialState: state) { BookRoutePreviewFeature() }
            await store.send(.routeRequestChanged(request)) {
                $0.routeRequestID = 1
                $0.previewSession = nil
                $0.routeFloorID = nil
                $0.isLoadingRoute = true
            }
            await store.receive(\.routeFailed) {
                $0.isLoadingRoute = false
                $0.routeError = IndoorRoutingError.noRoute.localizedDescription
            }
            #expect(store.state.readySession == nil)
            await store.finish()
        }

        @Test("화면 종료 후 도착한 계산 결과를 다시 표시하지 않는다")
        func invalidatesOnDisappear() async throws {
            let session = try NavigationGuidanceTestFixture.session()
            let request = readyState(session).routeRequest
            var state = BookRoutePreviewFeature.State()
            state.isLoadingRoute = true
            let store = TestStore(initialState: state) { BookRoutePreviewFeature() }
            await store.send(.disappeared) {
                $0.routeRequestID = 1
                $0.isLoadingRoute = false
            }
            await store.send(.routeLoaded(requestID: 0, request: request, session))
            #expect(store.state.previewSession == nil)
            await store.finish()
        }

        @Test("테스트모드 전환·화면 종료는 진행 중 경로 계산을 실제로 취소한다", arguments: [false, true])
        func cancelsPendingRoute(switchesToTestMode: Bool) async throws {
            let session = try NavigationGuidanceTestFixture.session()
            let state = readyState(session)
            let request = state.routeRequest
            let started = AsyncStream<Void>.makeStream()
            let cancelled = AsyncStream<Void>.makeStream()
            defer { started.continuation.finish(); cancelled.continuation.finish() }
            let store = TestStore(initialState: state) { BookRoutePreviewFeature() } withDependencies: {
                $0.bookRoutePreviewClient.load = { _, _, _ in
                    started.continuation.yield(())
                    do { try await Task.sleep(for: .seconds(60)) }
                    catch {
                        if Task.isCancelled { cancelled.continuation.yield(()) }
                        throw error
                    }
                    return session
                }
                $0.indoorMapClient.load = { throw CancellationError() }
            }
            // 자식 지도 로딩의 전이는 기존 BookShelfMapFeatureTests에서 검증한다.
            store.exhaustivity = .off(showSkippedAssertions: false)
            await store.send(.routeRequestChanged(request))
            var startedIterator = started.stream.makeAsyncIterator()
            #expect(await startedIterator.next() != nil)
            await store.send(switchesToTestMode ? .testModeButtonTapped : .disappeared)
            await store.finish()
            var cancelledIterator = cancelled.stream.makeAsyncIterator()
            #expect(await cancelledIterator.next() != nil)
            #expect(!store.state.isLoadingRoute)
            if switchesToTestMode {
                #expect(store.state.destination.isTestMode)
                #expect(store.state.shelfMap?.books == BookRoutePreviewSample.testItems.map(\.book))
                #expect(store.state.previewSession == nil)
            }
        }

        private func readyState(_ session: BookNavigationSession) -> BookRoutePreviewFeature.State {
            var state = BookRoutePreviewFeature.State(books: session.stops.map(\.book))
            state.shelfMap?.map.map = session.map
            state.shelfMap?.map.shelfLabels = session.shelfLabels
            for stop in session.stops {
                state.shelfMap?.holdings[stop.book.id] = .loaded(stop.holdings)
                state.shelfMap?.resolutions[stop.book.id] = stop.holdings.map {
                    .init(holding: $0, outcome: .candidates([stop.shelf]))
                }
            }
            return state
        }
    }
}
