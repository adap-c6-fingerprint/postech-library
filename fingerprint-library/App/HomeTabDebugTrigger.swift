#if DEBUG
import Foundation
import SwiftUI
import UIKit

/// 탭 선택값이 바뀌지 않는 홈 재선택도 세며, 느린 입력이나 다른 탭은 순서를 끊는다.
nonisolated struct HomeTabTapSequence {
    private var count = 0
    private var previousTap: TimeInterval?

    mutating func register(isHome: Bool, at time: TimeInterval) -> Bool {
        guard isHome else { reset(); return false }
        if let previousTap, (0...1).contains(time - previousTap) {
            count += 1
        } else {
            count = 1
        }
        previousTap = time
        guard count == 5 else { return false }
        reset()
        return true
    }

    mutating func reset() {
        count = 0
        previousTap = nil
    }
}

/// SwiftUI의 탭 delegate를 교체하지 않고 실제 탭바 터치를 관찰한다.
struct HomeTabDebugTrigger: UIViewControllerRepresentable {
    let isEnabled: Bool
    let isHomeSelected: () -> Bool
    let onActivate: () -> Void

    func makeUIViewController(context: Context) -> Controller {
        Controller(isEnabled: isEnabled, isHomeSelected: isHomeSelected, onActivate: onActivate)
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.isEnabled = isEnabled
        controller.isHomeSelected = isHomeSelected
        controller.onActivate = onActivate
        controller.attachIfPossible()
        DispatchQueue.main.async { [weak controller] in controller?.attachIfPossible() }
    }

    static func dismantleUIViewController(_ controller: Controller, coordinator: ()) {
        controller.tearDown()
    }

    final class Controller: UIViewController, UIGestureRecognizerDelegate {
        var onActivate: () -> Void
        var isHomeSelected: () -> Bool
        var isEnabled: Bool {
            didSet {
                guard isEnabled != oldValue else { return }
                tapRecognizer.isEnabled = isEnabled
                sequence.reset()
            }
        }
        private(set) weak var observedTabController: UITabBarController?
        private var sequence = HomeTabTapSequence()
        private var isInvalidated = false
        private(set) lazy var tapRecognizer: UITapGestureRecognizer = {
            let recognizer = UITapGestureRecognizer(target: self, action: #selector(tabBarTapped(_:)))
            recognizer.cancelsTouchesInView = false
            recognizer.delaysTouchesBegan = false
            recognizer.delaysTouchesEnded = false
            recognizer.delegate = self
            recognizer.isEnabled = isEnabled
            return recognizer
        }()

        init(isEnabled: Bool, isHomeSelected: @escaping () -> Bool, onActivate: @escaping () -> Void) {
            self.isEnabled = isEnabled
            self.isHomeSelected = isHomeSelected
            self.onActivate = onActivate
            super.init(nibName: nil, bundle: nil)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func loadView() {
            view = UIView()
            view.isUserInteractionEnabled = false
            view.backgroundColor = .clear
        }

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            attachIfPossible()
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            attachIfPossible()
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            attachIfPossible()
        }

        func attachIfPossible() {
            guard !isInvalidated else { return }
            var ancestor = parent
            while let candidate = ancestor {
                if let tabs = findTabController(in: candidate) {
                    if observedTabController !== tabs || tapRecognizer.view !== tabs.tabBar {
                        tapRecognizer.view?.removeGestureRecognizer(tapRecognizer)
                        observedTabController = tabs
                        tabs.tabBar.addGestureRecognizer(tapRecognizer)
                        sequence.reset()
                    }
                    return
                }
                ancestor = candidate.parent
            }
        }

        func tearDown() {
            isInvalidated = true
            isEnabled = false
            tapRecognizer.view?.removeGestureRecognizer(tapRecognizer)
            observedTabController = nil
        }

        /// UIKit이 기본 탭 선택을 끝낸 뒤 호출한다. 같은 홈 탭의 반복 입력도 처리한다.
        func recordCompletedTabTap(at time: TimeInterval) {
            guard isEnabled, observedTabController != nil else { return }
            if sequence.register(isHome: isHomeSelected(), at: time) { onActivate() }
        }

        @objc private func tabBarTapped(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended else { return }
            let time = ProcessInfo.processInfo.systemUptime
            // 선택 동작을 취소하거나 지연하지 않고, 이번 터치의 최종 선택을 읽는다.
            DispatchQueue.main.async { [weak self] in self?.recordCompletedTabTap(at: time) }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard let view = touch.view, let tabBar = observedTabController?.tabBar else { return false }
            return Self.isTabControlTouch(view, in: tabBar)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }

        static func isTabControlTouch(_ view: UIView, in tabBar: UITabBar) -> Bool {
            guard view.isDescendant(of: tabBar) else { return false }
            var candidate: UIView? = view
            while let current = candidate, current !== tabBar {
                if current is UITextField { return false }
                if current is UIControl { return true }
                candidate = current.superview
            }
            return false
        }

        private func findTabController(in controller: UIViewController) -> UITabBarController? {
            if let tabs = controller as? UITabBarController { return tabs }
            for child in controller.children {
                if let tabs = findTabController(in: child) { return tabs }
            }
            return nil
        }
    }
}
#endif
