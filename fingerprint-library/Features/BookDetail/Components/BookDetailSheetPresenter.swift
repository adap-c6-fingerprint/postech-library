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
    /// App이 경로 미리보기를 전체 화면으로 띄우는 동안 시트를 내려 둔다.
    var isSuspended = false
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
        controller.setSuspended(isSuspended)
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
        private var compactFrameReportTask: Task<Void, Never>?
        private var hasPresented = false
        private var didFinishPresentation = false
        private var isInvalidated = false
        private var isSuspended = false
        private var resumeTask: Task<Void, Never>?
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
                self?.scheduleCompactFrameReport()
            }
            let hosting = UIHostingController(rootView: content)
            hosting.modalPresentationStyle = .pageSheet
            hosting.view.backgroundColor = .clear
            hosting.overrideUserInterfaceStyle = .dark
            self.hosting = hosting
            presentSheet(hosting)
        }

        private func presentSheet(_ hosting: UIHostingController<BookDetailSheet>) {
            didFinishPresentation = false
            presentation.detent = .medium
            // 시트를 닫았다가 다시 띄우면 시스템이 시트 설정을 새로 만들므로 띄울 때마다 설정한다.
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
            present(hosting, animated: true) { [weak self, weak hosting] in
                guard let self, !self.isInvalidated else {
                    hosting?.presentingViewController?.dismiss(animated: false)
                    return
                }
                self.didFinishPresentation = true
                self.reportCompactFrame()
            }
        }

        private func scheduleCompactFrameReport() {
            compactFrameReportTask?.cancel()
            guard !isInvalidated, didFinishPresentation, !presentation.isExpanded else { return }
            // 드래그 중 바뀌는 모든 프레임에 지도 카메라를 다시 맞추지 않는다.
            compactFrameReportTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(120))
                guard !Task.isCancelled else { return }
                self?.reportCompactFrame()
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
            // 높이 전환 애니메이션은 시스템 시트가 처리한다.
            switch sheetPresentationController.selectedDetentIdentifier {
            case Self.compactID: presentation.detent = .compact
            case .large: presentation.detent = .large
            default: presentation.detent = .medium
            }
            scheduleCompactFrameReport()
        }

        // 높이 전환은 유지하고 아래로 당겨 상세를 닫는 동작만 막는다.
        func presentationControllerShouldDismiss(_ presentationController: UIPresentationController) -> Bool {
            false
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

        /// 전체 화면 안내가 뜨기 전에 시트를 내리고, 안내가 완전히 닫힌 뒤 같은 시트를 다시 띄운다.
        ///
        /// 시트를 띄운 채로 앱 루트가 전체 화면을 띄우면 시스템이 시트를 내려 버려 상세로 돌아와도 시트가 없다.
        func setSuspended(_ suspended: Bool) {
            guard isSuspended != suspended else { return }
            isSuspended = suspended
            resumeTask?.cancel()
            guard hasPresented, !isInvalidated, let hosting else { return }
            if suspended {
                compactFrameReportTask?.cancel()
                hosting.presentingViewController?.dismiss(animated: false)
                return
            }
            resumeTask = Task { [weak self, weak hosting] in
                // 전체 화면 안내의 닫힘 전환이 끝날 때까지 기다린다. 2초가 지나면 포기한다.
                for _ in 0..<40 {
                    guard let self, let hosting, !Task.isCancelled, !self.isInvalidated, !self.isSuspended else { return }
                    if let window = self.view.window, window.rootViewController?.presentedViewController == nil {
                        self.presentSheet(hosting)
                        return
                    }
                    try? await Task.sleep(for: .milliseconds(50))
                }
            }
        }

        func tearDown() {
            resumeTask?.cancel()
            guard !isInvalidated else { return }
            isInvalidated = true
            // 상세에서 연 모달까지 함께 닫는다.
            hosting?.presentingViewController?.dismiss(animated: false)
            hosting = nil
        }

    }
}
