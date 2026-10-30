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
    }
}

