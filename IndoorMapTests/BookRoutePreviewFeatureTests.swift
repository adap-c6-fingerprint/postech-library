//
//  BookRoutePreviewFeatureTests.swift
//  IndoorMapTests
//
//  Created by Youngmin Cho on 10/31/26.
//

import Foundation
import Testing
import ComposableArchitecture
@testable import fingerprint_library

extension IndoorMapSerialTests {
    @MainActor
    struct BookRoutePreviewFeatureTests {
        @Test("경로 계산 실패 시 로딩을 끝내고 오류를 저장한다")
        func handlesRouteFailure() async throws {
            // 기존 테스트 도구로 가짜 지도, 서가, 책을 준비
            let sample = try NavigationGuidanceTestFixture.session()
            let message = IndoorRoutingError.noRoute.localizedDescription

            let store = TestStore(
                initialState: BookRoutePreviewFeature.State()
            ) {
                BookRoutePreviewFeature()
            } withDependencies: {
                // 실제 로더 대신 항상 실패하는 Client를 사용
                $0.bookRoutePreviewClient = .testValue
            }

            // 경로 요청을 보내면 로딩이 시작되어야 함
            await store.send(.requestChanged(.ready(
                map: sample.map,
                labels: sample.shelfLabels,
                stops: sample.stops
            ))) {
                $0.requestID = 1
                $0.isLoadingRoute = true
            }

            // Feature가 실패 Action을 보내면 상태가 바뀌어야 함
            await store.receive(.routeFailed(requestID: 1, message)) {
                $0.isLoadingRoute = false
                $0.routeError = message
            }

            #expect(store.state.previewSession == nil)
            await store.finish()
        }

        @Test("이전 요청의 결과는 무시하고 현재 요청의 결과만 반영한다")
        func ignoresPreviousRequestResults() async throws {
            let session = try NavigationGuidanceTestFixture.session()

            // 2번 요청을 계산 중인 상황에서 시작
            var initial = BookRoutePreviewFeature.State()
            initial.requestID = 2
            initial.isLoadingRoute = true

            let store = TestStore(initialState: initial) {
                BookRoutePreviewFeature()
            }

            // 이전 1번 요청의 성공, 실패는 상태를 바꾸면 안 됨
            await store.send(.routeLoaded(requestID: 1, session))
            await store.send(.routeFailed(requestID: 1, "이전 요청 오류"))

            // 현재 2번 요청의 성공은 반영해야 함
            await store.send(.routeLoaded(requestID: 2, session)) {
                $0.isLoadingRoute = false
                $0.previewSession = session
            }

            await store.finish()
        }
        @Test("재시도는 이전 오류를 지우고 전달한 입력의 계산 결과를 저장한다")
        func loadsSessionAfterFailure() async throws {
            let sample = try NavigationGuidanceTestFixture.session()
            var initial = BookRoutePreviewFeature.State()
            initial.routeError = "이전 계산 실패"

            let store = TestStore(initialState: initial) {
                BookRoutePreviewFeature()
            } withDependencies: {
                $0.bookRoutePreviewClient.load = { map, labels, stops in
                    await MainActor.run {
                        #expect(map == sample.map)
                        #expect(labels == sample.shelfLabels)
                        #expect(stops == sample.stops)
                    }
                    return sample
                }
            }

            await store.send(.requestChanged(.ready(
                map: sample.map, labels: sample.shelfLabels, stops: sample.stops
            ))) {
                $0.requestID = 1
                $0.isLoadingRoute = true
                $0.routeError = nil
            }
            await store.receive(.routeLoaded(requestID: 1, sample)) {
                $0.isLoadingRoute = false
                $0.previewSession = sample
            }
            await store.finish()
        }

        @Test("화면 종료는 진행 중 계산을 취소하고 늦은 응답을 무시한다")
        func cancelsRouteOnDisappear() async throws {
            let sample = try NavigationGuidanceTestFixture.session()
            let pending = SuspendedRouteLoad()
            let store = TestStore(initialState: BookRoutePreviewFeature.State()) {
                BookRoutePreviewFeature()
            } withDependencies: {
                $0.bookRoutePreviewClient.load = { _, _, _ in
                    try await pending.load(sample)
                }
            }

            await store.send(.requestChanged(.ready(
                map: sample.map, labels: sample.shelfLabels, stops: sample.stops
            ))) {
                $0.requestID = 1
                $0.isLoadingRoute = true
            }
            await pending.clock.advance()
            try #require(pending.didStart.value)

            await store.send(.disappeared) {
                $0.requestID = 2
                $0.isLoadingRoute = false
            }
            await store.finish(timeout: .seconds(1))
            #expect(pending.didCancel.value)

            await store.send(.routeLoaded(requestID: 1, sample))
            await store.send(.routeFailed(requestID: 1, "종료 전 요청의 오류"))
            #expect(store.state.previewSession == nil)
            #expect(store.state.routeError == nil)
        }

        @Test("초기화는 진행 중 계산을 취소하고 다음 목적지를 기다린다")
        func resetsPendingRoute() async throws {
            let sample = try NavigationGuidanceTestFixture.session()
            let pending = SuspendedRouteLoad()
            let store = TestStore(initialState: BookRoutePreviewFeature.State()) {
                BookRoutePreviewFeature()
            } withDependencies: {
                $0.bookRoutePreviewClient.load = { _, _, _ in
                    try await pending.load(sample)
                }
            }

            await store.send(.requestChanged(.ready(
                map: sample.map, labels: sample.shelfLabels, stops: sample.stops
            ))) {
                $0.requestID = 1
                $0.isLoadingRoute = true
            }
            await pending.clock.advance()
            try #require(pending.didStart.value)

            await store.send(.reset) {
                $0.requestID = 2
                $0.isLoadingRoute = false
            }
            await store.finish(timeout: .seconds(1))
            #expect(pending.didCancel.value)
            await store.send(.routeLoaded(requestID: 1, sample))
            #expect(store.state.previewSession == nil)
            #expect(store.state.routeError == nil)
        }

        @Test("새 목적지 요청은 이전 계산을 취소하고 새 결과만 표시한다")
        func replacesPendingRoute() async throws {
            let first = try NavigationGuidanceTestFixture.session()
            let second = try NavigationGuidanceTestFixture.session()
            let firstVenueID = first.map.venue.sourceID
            let pending = SuspendedRouteLoad()
            let store = TestStore(initialState: BookRoutePreviewFeature.State()) {
                BookRoutePreviewFeature()
            } withDependencies: {
                $0.bookRoutePreviewClient.load = { map, _, _ in
                    if map.venue.sourceID == firstVenueID {
                        return try await pending.load(first)
                    }
                    return second
                }
            }

            await store.send(.requestChanged(.ready(
                map: first.map, labels: first.shelfLabels, stops: first.stops
            ))) {
                $0.requestID = 1
                $0.isLoadingRoute = true
            }
            await pending.clock.advance()
            try #require(pending.didStart.value)

            await store.send(.requestChanged(.ready(
                map: second.map, labels: second.shelfLabels, stops: second.stops
            ))) {
                $0.requestID = 2
            }
            await store.receive(.routeLoaded(requestID: 2, second)) {
                $0.isLoadingRoute = false
                $0.previewSession = second
            }
            await store.finish(timeout: .seconds(1))
            #expect(pending.didCancel.value)

            await store.send(.routeLoaded(requestID: 1, first))
            #expect(store.state.previewSession == second)
        }

        @Test("화면 종료는 완료된 결과를 보존하고 초기화는 결과를 지운다")
        func preservesCompletedSessionUntilReset() async throws {
            let sample = try NavigationGuidanceTestFixture.session()
            var initial = BookRoutePreviewFeature.State()
            initial.previewSession = sample
            initial.requestID = 1
            let store = TestStore(initialState: initial) {
                BookRoutePreviewFeature()
            }

            await store.send(.disappeared) {
                $0.requestID = 2
            }
            #expect(store.state.previewSession == sample)
            await store.send(.reset) {
                $0.requestID = 3
                $0.previewSession = nil
            }
            await store.finish()
        }

        /// 실제 파일·시간을 사용하지 않고, 취소될 때까지 계산을 보류
        private nonisolated final class SuspendedRouteLoad: Sendable {
            let clock = TestClock<Duration>()
            let didStart = LockIsolated(false)
            let didCancel = LockIsolated(false)

            func load(_ session: BookNavigationSession) async throws -> BookNavigationSession {
                try await withTaskCancellationHandler {
                    didStart.setValue(true)
                    try await clock.sleep(for: .seconds(3_600))
                    return session
                } onCancel: {
                    self.didCancel.setValue(true)
                }
            }
        }

    }
}
