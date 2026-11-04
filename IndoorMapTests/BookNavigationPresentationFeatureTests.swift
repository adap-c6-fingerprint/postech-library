import ComposableArchitecture
import Testing
@testable import fingerprint_library

extension IndoorMapSerialTests {
    @MainActor
    struct BookNavigationPresentationFeatureTests {
        @Test("현재 책에 도착하기 전에도 현재 위치에서 다음 책으로 다시 안내한다")
        func skipUnreachedStopFromCurrentPosition() async throws {
            let session = try NavigationGuidanceTestFixture.session()
            let position = NavigationGuidanceTestFixture.position(x: 5)
            let route = NavigationGuidanceTestFixture.make(nodes: [IndoorRoutingTestFactory.node("a"),
                IndoorRoutingTestFactory.node("b", x: 20)], reversed: true, projectedStart: position.coordinate).route
            let recalculated = try BookNavigationSession(map: session.map, shelfLabels: session.shelfLabels,
                stops: [session.stops[1]], legs: [route], graph: session.graph, start: position)
            var initial = BookNavigationFeature.State(session: session)
            initial.isCancelConfirmationPresented = true
            initial.rawPosition = position
            initial.latestPosition = position
            initial.progress = try initial.currentPlan?.progress(for: position, at: position.timestamp)
            let store = TestStore(initialState: initial) { BookNavigationFeature() } withDependencies: {
                $0.date = .constant(position.timestamp)
                $0.bookRoutePreviewClient.load = { _, _, start, stops in
                    #expect(start == position)
                    await MainActor.run {
                        #expect(stops.map(\.book.id) == [session.stops[1].book.id])
                        #expect(stops[0].candidateShelves == [session.stops[1].shelf])
                    }
                    return recalculated
                }
            }
            store.exhaustivity = .off
            await store.send(.nextBookTapped)
            await store.receive(.nextBookRouteLoaded(requestID: 1, stopIndex: 1, route))
            #expect(store.state.currentStopIndex == 1)
            #expect(store.state.currentStop?.book == session.stops[1].book)
            #expect(store.state.currentRoute?.start.actualCoordinate == position.coordinate)
            #expect(store.state.currentRoute != session.legs[1], "이전 서가를 출발점으로 둔 경로를 재사용하면 안 됩니다")
            #expect(store.state.currentPlan?.destination.id == route.nodeIDs.last)
            #expect(!store.state.isReroutingToNextBook)
            #expect(!store.state.isCancelConfirmationPresented)
            await store.finish()
        }

        @Test("현재 서가 도착 후에도 현재 위치에서 다음 책 경로로 전환한다")
        func nextBookAfterArrival() async throws {
            let session = try NavigationGuidanceTestFixture.session()
            let position = NavigationGuidanceTestFixture.position(x: 20, y: 19)
            let route = NavigationGuidanceTestFixture.make(reversed: true, projectedStart: position.coordinate).route
            let recalculated = try BookNavigationSession(map: session.map, shelfLabels: session.shelfLabels,
                stops: [session.stops[1]], legs: [route], graph: session.graph, start: position)
            var initial = BookNavigationFeature.State(session: session)
            initial.isCancelConfirmationPresented = true
            initial.isArrivalPresented = true
            initial.automaticallyArrivedStopIndices = [0]
            initial.rawPosition = position
            initial.latestPosition = position
            initial.progress = try initial.currentPlan?.progress(for: position, at: position.timestamp)
            #expect(initial.progress?.maneuver == .nearDestination)
            let store = TestStore(initialState: initial) { BookNavigationFeature() } withDependencies: {
                $0.date = .constant(position.timestamp)
                $0.bookRoutePreviewClient.load = { _, _, start, _ in
                    #expect(start == position)
                    return recalculated
                }
            }
            store.exhaustivity = .off
            await store.send(.nextBookTapped)
            await store.receive(.nextBookRouteLoaded(requestID: 1, stopIndex: 1, route))
            #expect(store.state.currentStop?.book == session.stops[1].book)
            #expect(store.state.currentRoute == route)
            #expect(store.state.currentRoute?.start.actualCoordinate == position.coordinate)
            #expect(store.state.currentRoute != session.legs[1], "재계산된 경로를 무시하면 안 됩니다")
            #expect(!store.state.isArrivalPresented)
            #expect(!store.state.isReroutingToNextBook)
            await store.send(.nextBookTapped)
            await store.finish()
        }

        @Test("시트 높이가 바뀌어도 사용자가 해제한 자동 카메라 추적을 재개하지 않는다")
        func sheetKeepsManualCamera() async throws {
            var initial = BookNavigationFeature.State(session: try NavigationGuidanceTestFixture.session())
            initial.followsNavigationCamera = false
            let store = TestStore(initialState: initial) { BookNavigationFeature() }
            await store.send(.viewportChanged)
            await store.finish()
        }
    }
}
