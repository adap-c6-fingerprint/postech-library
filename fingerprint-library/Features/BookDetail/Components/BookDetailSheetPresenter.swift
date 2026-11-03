import ComposableArchitecture
import Observation
import SwiftUI
import UIKit

@MainActor @Observable
final class BookDetailSheetPresentation {
    var isExpanded = false
}

/// 책 상세 네이티브 시트의 표시·종료를 소유한다.
struct BookDetailSheetPresenter: UIViewControllerRepresentable {
    let store: StoreOf<BookDetailFeature>
    let presentation: BookDetailSheetPresentation
    var onDismiss: () -> Void
    var onFrameChange: (CGRect) -> Void

    func makeUIViewController(context: Context) -> Controller {
        Controller(store: store, presentation: presentation, onDismiss: onDismiss, onFrameChange: onFrameChange)
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.onDismiss = onDismiss
        controller.onFrameChange = onFrameChange
    }

    static func dismantleUIViewController(_ controller: Controller, coordinator: ()) {
        controller.tearDown()
    }

    final class Controller: UIViewController, UISheetPresentationControllerDelegate {
        private let store: StoreOf<BookDetailFeature>
        var onDismiss: () -> Void
        var onFrameChange: (CGRect) -> Void
        private var hosting: UIHostingController<BookDetailSheet>?
        private var hasPresented = false
        private var isInvalidated = false
        private let presentation: BookDetailSheetPresentation

        init(store: StoreOf<BookDetailFeature>, presentation: BookDetailSheetPresentation, onDismiss: @escaping () -> Void,
             onFrameChange: @escaping (CGRect) -> Void) {
            self.store = store
            self.presentation = presentation
            self.onDismiss = onDismiss
            self.onFrameChange = onFrameChange
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
            presentation.isExpanded = false
            let content = BookDetailSheet(store: store, presentation: presentation, onDismiss: { [weak self] in
                self?.dismissDetail()
            }) { [weak self] _ in
                self?.reportSheetFrame()
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
                self.reportSheetFrame()
            }
        }

        /// 실제 시트 위치를 뒤쪽 SwiftUI 화면과 같은 좌표계로 전달한다.
        private func reportSheetFrame() {
            guard !isInvalidated, let hosting, hosting.view.window != nil else { return }
            let frame = hosting.view.convert(hosting.view.bounds, to: view)
            guard frame.minY.isFinite, frame.height.isFinite, frame.height > 0 else { return }
            onFrameChange(frame)
        }

        func sheetPresentationControllerDidChangeSelectedDetentIdentifier(_ sheetPresentationController: UISheetPresentationController) {
            guard !isInvalidated else { return }
            withAnimation(.easeInOut(duration: 0.25)) {
                presentation.isExpanded = sheetPresentationController.selectedDetentIdentifier == .large
            }
        }

        private func dismissDetail() {
            guard !isInvalidated else { return }
            isInvalidated = true
            let onDismiss = onDismiss
            hosting?.dismiss(animated: true, completion: onDismiss)
            hosting = nil
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
