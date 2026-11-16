import ComposableArchitecture
import Foundation
import Testing
import UIKit
@testable import fingerprint_library

@MainActor
@Suite(.serialized)
struct BookDetailSheetHandoffTests {
    @Test(arguments: [false, true])
    func 상세_시트_닫힘_뒤_새_모달을_열고_상세로_돌아온다(duringPresentation: Bool) async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let root = UIViewController()
        window.rootViewController = root
        let nextModal = UIViewController()
        let handoffs = LockIsolated(0)
        var state = BookDetailFeature.State(book: makeBook(1))
        state.hasLoaded = true
        state.holdingsState = .loaded([])
        let store = Store(initialState: state) {
            BookDetailFeature()
            Reduce<BookDetailFeature.State, BookDetailFeature.Action> { [weak root] _, action in
                if case .delegate(.startGuidance) = action {
                    #expect(root?.presentedViewController == nil, "상세 시트가 남아 있는 동안 새 모달을 열지 않는다")
                    handoffs.withValue { $0 += 1 }
                    root?.present(nextModal, animated: false)
                }
                return .none
            }
        } withDependencies: {
            $0.uuid = .incrementing
        }
        let mapStore = withDependencies {
            $0.uuid = .incrementing
        } operation: {
            Store(initialState: IndoorMapFeature.State()) { IndoorMapFeature() }
        }
        let controller = BookDetailSheetPresenter.Controller(
            store: store, mapStore: mapStore, presentation: BookDetailSheetPresentation(),
            onDismiss: { }, onCompactFrameChange: { _ in })
        root.addChild(controller)
        root.view.addSubview(controller.view)
        controller.view.frame = root.view.bounds
        controller.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        controller.didMove(toParent: root)
        defer {
            controller.tearDown()
            root.dismiss(animated: false)
            window.isHidden = true
            window.rootViewController = nil
            previousWindow?.makeKeyAndVisible()
        }
        window.makeKeyAndVisible()
        try await waitUntil { root.presentedViewController != nil }
        if !duringPresentation {
            try await waitUntil { root.presentedViewController?.isBeingPresented == false }
        }

        store.send(.guidanceStarted)
        controller.setSuspended(true)
        try await waitUntil { root.presentedViewController === nextModal }
        #expect(handoffs.value == 1)
        #expect(store.pendingGuidanceRequest == nil)

        await withCheckedContinuation { continuation in
            root.dismiss(animated: false) { continuation.resume() }
        }
        store.send(.guidanceDismissed)
        controller.setSuspended(false)
        try await waitUntil { root.presentedViewController != nil && root.presentedViewController !== nextModal }
        #expect(handoffs.value == 1)
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !condition() {
            guard ContinuousClock.now < deadline else {
                Issue.record("UIKit 화면 전환이 완료되지 않았다")
                throw HandoffError.timedOut
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private enum HandoffError: Error { case timedOut }
}
