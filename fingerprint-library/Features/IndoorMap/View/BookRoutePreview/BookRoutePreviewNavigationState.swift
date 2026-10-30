import Foundation

/// 내부 안내 cover가 닫힌 뒤에만 미리보기를 닫아, 모달·NavigationLink 진입 모두 원래 화면으로 복귀한다.
struct BookRoutePreviewNavigationState: Equatable {
    var session: BookNavigationSession?
    private(set) var returnsToOrigin = false

    mutating func start(_ session: BookNavigationSession?) {
        guard let session, self.session == nil, !returnsToOrigin else { return }
        self.session = session
    }

    mutating func navigationEnded() {
        guard session != nil else { return }
        returnsToOrigin = true
        session = nil
    }

    mutating func presentationDismissed() -> Bool {
        let result = returnsToOrigin
        returnsToOrigin = false
        return result
    }
}
