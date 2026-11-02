import ComposableArchitecture
import SwiftUI
import UIKit

/// 책 상세 네이티브 시트의 표시·종료를 소유한다.
struct BookDetailSheetPresenter: UIViewControllerRepresentable {
    let store: StoreOf<BookDetailFeature>
    var onDismiss: () -> Void
    var onHeightChange: (CGFloat) -> Void

    func makeUIViewController(context: Context) -> Controller {
        Controller(store: store, onDismiss: onDismiss, onHeightChange: onHeightChange)
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.onDismiss = onDismiss
        controller.onHeightChange = onHeightChange
    }

    static func dismantleUIViewController(_ controller: Controller, coordinator: ()) {
        controller.tearDown()
    }

    final class Controller: UIViewController, UISheetPresentationControllerDelegate {
        private let store: StoreOf<BookDetailFeature>
        var onDismiss: () -> Void
        var onHeightChange: (CGFloat) -> Void
        private var hosting: UIHostingController<BookDetailSheet>?
        private var hasPresented = false
        private var isInvalidated = false

        init(store: StoreOf<BookDetailFeature>, onDismiss: @escaping () -> Void,
             onHeightChange: @escaping (CGFloat) -> Void) {
            self.store = store
            self.onDismiss = onDismiss
            self.onHeightChange = onHeightChange
            super.init(nibName: nil, bundle: nil)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func loadView() {
            view = UIView()
            view.backgroundColor = .clear
            view.isUserInteractionEnabled = false
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            guard !hasPresented, !isInvalidated, view.window != nil else { return }
            hasPresented = true
            let content = BookDetailSheet(store: store) { [weak self] height in
                guard let self, !self.isInvalidated else { return }
                self.onHeightChange(height)
            }
            let hosting = UIHostingController(rootView: content)
            hosting.modalPresentationStyle = .pageSheet
            hosting.view.backgroundColor = .clear
            hosting.overrideUserInterfaceStyle = .dark
            if let sheet = hosting.sheetPresentationController {
                let compactID = UISheetPresentationController.Detent.Identifier("bookDetail.compact")
                sheet.detents = [.custom(identifier: compactID) { $0.maximumDetentValue * 0.52 }, .large()]
                sheet.selectedDetentIdentifier = compactID
                sheet.prefersGrabberVisible = false
                sheet.preferredCornerRadius = 28
                sheet.largestUndimmedDetentIdentifier = compactID
                // 기본 Liquid Glass와 높이에 따른 재질 전환은 시스템에 맡긴다.
                sheet.delegate = self
            }
            self.hosting = hosting
            present(hosting, animated: true) { [weak self, weak hosting] in
                guard let self, !self.isInvalidated else {
                    hosting?.presentingViewController?.dismiss(animated: false)
                    return
                }
            }
        }

        func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
            guard !isInvalidated else { return }
            isInvalidated = true
            hosting = nil
            onDismiss()
        }

        func tearDown() {
            guard !isInvalidated else { return }
            isInvalidated = true
            // 상세에서 연 모달까지 함께 닫는다.
            hosting?.presentingViewController?.dismiss(animated: false)
            hosting = nil
        }

    }
}
