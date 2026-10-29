import Testing
@testable import fingerprint_library

@MainActor
struct BookRoutePreviewNavigationStateTests {
    @Test("취소·완료 시 내부 cover를 먼저 닫고 닫힘 콜백에서 한 번만 원래 화면 복귀를 요청한다")
    func dismissesInOrder() throws {
        let session = try NavigationGuidanceTestFixture.session()
        var flow = BookRoutePreviewNavigationState()
        flow.start(session)
        #expect(flow.session == session && !flow.returnsToOrigin)
        flow.navigationEnded()
        #expect(flow.session == nil && flow.returnsToOrigin)
        flow.navigationEnded()
        flow.start(session)
        #expect(flow.session == nil)
        let firstDismissal = flow.presentationDismissed()
        let duplicateDismissal = flow.presentationDismissed()
        #expect(firstDismissal)
        #expect(!duplicateDismissal)
        #expect(!flow.returnsToOrigin)
    }

    @Test("준비되지 않은 출발과 종료 확인 없는 cover 닫힘은 원래 화면까지 되돌리지 않는다")
    func preservesPreview() throws {
        var flow = BookRoutePreviewNavigationState()
        flow.start(nil)
        let emptyDismissal = flow.presentationDismissed()
        #expect(flow.session == nil && !emptyDismissal)
        flow.start(try NavigationGuidanceTestFixture.session())
        flow.session = nil
        let unconfirmedDismissal = flow.presentationDismissed()
        #expect(!unconfirmedDismissal)
    }
}
