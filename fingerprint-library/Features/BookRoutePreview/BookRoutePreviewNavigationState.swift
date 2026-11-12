import Foundation

/// 내부 안내 cover가 닫힌 뒤에만 미리보기를 닫아, 모달·NavigationLink 진입 모두 원래 화면으로 복귀한다.
struct BookRoutePreviewNavigationState: Equatable {
    var routePlan: RoutePlan?
    private(set) var returnsToOrigin = false

    mutating func start(_ routePlan: RoutePlan?) {
        guard let routePlan, self.routePlan == nil, !returnsToOrigin else { return }
        self.routePlan = routePlan
    }

    mutating func navigationEnded() {
        guard routePlan != nil else { return }
        returnsToOrigin = true
        routePlan = nil
    }

    mutating func presentationDismissed() -> Bool {
        let result = returnsToOrigin
        returnsToOrigin = false
        return result
    }
}
