import ComposableArchitecture
import Observation
import SwiftUI
import UIKit

@MainActor @Observable
final class BookDetailSheetPresentation {
    var detent: BookDetailSheetDetent = .medium
    var isExpanded: Bool { detent == .large }
}

/// 책 상세 네이티브 시트의 표시·종료를 소유한다.
struct BookDetailSheetPresenter: UIViewControllerRepresentable {
    let store: StoreOf<BookDetailFeature>
    let mapStore: StoreOf<IndoorMapFeature>
    let presentation: BookDetailSheetPresentation
    var onDismiss: () -> Void
    var onCompactFrameChange: (CGRect) -> Void

    func makeUIViewController(context: Context) -> Controller {
        Controller(
            store: store, mapStore: mapStore, presentation: presentation,
            onDismiss: onDismiss, onCompactFrameChange: onCompactFrameChange)
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.onDismiss = onDismiss
        controller.onCompactFrameChange = onCompactFrameChange
    }

    static func dismantleUIViewController(_ controller: Controller, coordinator: ()) {
        controller.tearDown()
    }

    final class Controller: UIViewController, UISheetPresentationControllerDelegate {
        static let compactID = UISheetPresentationController.Detent.Identifier("bookDetail.compact")

        private let store: StoreOf<BookDetailFeature>
        private let mapStore: StoreOf<IndoorMapFeature>
        var onDismiss: () -> Void
        var onCompactFrameChange: (CGRect) -> Void
        private var hosting: UIHostingController<BookDetailSheet>?
        private var hasPresented = false
        private var didFinishPresentation = false
        private var isInvalidated = false
        private let presentation: BookDetailSheetPresentation

        init(
            store: StoreOf<BookDetailFeature>, mapStore: StoreOf<IndoorMapFeature>,
            presentation: BookDetailSheetPresentation, onDismiss: @escaping () -> Void,
            onCompactFrameChange: @escaping (CGRect) -> Void
        ) {
            self.store = store
            self.mapStore = mapStore
            self.presentation = presentation
            self.onDismiss = onDismiss
            self.onCompactFrameChange = onCompactFrameChange
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
            presentation.detent = .medium
            let content = BookDetailSheet(store: store, mapStore: mapStore, presentation: presentation, onDismiss: { [weak self] in
                self?.dismissDetail()
            }) { [weak self] in
                self?.reportCompactFrame()
            }
            let hosting = UIHostingController(rootView: content)
            hosting.modalPresentationStyle = .pageSheet
            hosting.view.backgroundColor = .clear
            hosting.overrideUserInterfaceStyle = .dark
            if let sheet = hosting.sheetPresentationController {
                sheet.detents = [.custom(identifier: Self.compactID) { context in
                    let height = UIFontMetrics(forTextStyle: .body).scaledValue(
                        for: BookDetailCompactLayout.height,
                        compatibleWith: context.containerTraitCollection)
                    // 가로 화면·큰 글자에서 medium보다 낮은 요약 화면을 확보할 수 없으면 생략한다.
                    guard let medium = UISheetPresentationController.Detent.medium().resolvedValue(in: context),
                          height < medium else { return nil }
                    return height
                }, .medium(), .large()]
                sheet.selectedDetentIdentifier = .medium
                sheet.prefersGrabberVisible = false
                sheet.preferredCornerRadius = 28
                sheet.largestUndimmedDetentIdentifier = .medium
                // 기본 Liquid Glass와 높이에 따른 재질 전환은 시스템에 맡긴다.
                sheet.delegate = self
            }
            self.hosting = hosting
            present(hosting, animated: true) { [weak self, weak hosting] in
                guard let self, !self.isInvalidated else {
                    hosting?.presentingViewController?.dismiss(animated: false)
                    return
                }
                self.didFinishPresentation = true
                self.reportCompactFrame()
            }
        }

        /// compact·medium의 실제 위치를 지도에 전달하고 large에서는 마지막 위치를 유지한다.
        private func reportCompactFrame() {
            guard !isInvalidated, didFinishPresentation, let hosting, hosting.view.window != nil,
                  hosting.sheetPresentationController?.selectedDetentIdentifier != .large
            else { return }
            let frame = hosting.view.convert(hosting.view.bounds, to: view)
            guard frame.minY.isFinite, frame.height.isFinite, frame.height > 0 else { return }
            onCompactFrameChange(frame)
        }

        func sheetPresentationControllerDidChangeSelectedDetentIdentifier(_ sheetPresentationController: UISheetPresentationController) {
            guard !isInvalidated else { return }
            withAnimation(.easeInOut(duration: 0.25)) {
                switch sheetPresentationController.selectedDetentIdentifier {
                case Self.compactID: presentation.detent = .compact
                case .large: presentation.detent = .large
                default: presentation.detent = .medium
                }
            }
            reportCompactFrame()
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
