import ComposableArchitecture
import Observation
import SwiftUI
import UIKit

@MainActor @Observable
final class BookDetailSheetPresentation {
    var detent: BookDetailSheetDetent = .medium
    var isExpanded: Bool { detent == .large }
}

struct BookDetailSheetPresenter: UIViewControllerRepresentable {
    let store: StoreOf<BookDetailFeature>
    let mapStore: StoreOf<IndoorMapFeature>
    let presentation: BookDetailSheetPresentation
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
            if let sheet = hosting.sheetPresentationController {
                sheet.detents = [.custom(identifier: Self.compactID) { context in
                    let height = UIFontMetrics(forTextStyle: .body).scaledValue(
                        for: BookDetailCompactLayout.height,
                        compatibleWith: context.containerTraitCollection)
                    guard let medium = UISheetPresentationController.Detent.medium().resolvedValue(in: context),
                          height < medium else { return nil }
                    return height
                }, .medium(), .large()]
                sheet.selectedDetentIdentifier = .medium
                sheet.prefersGrabberVisible = false
                sheet.preferredCornerRadius = 28
                sheet.largestUndimmedDetentIdentifier = .medium
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
            compactFrameReportTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(120))
                guard !Task.isCancelled else { return }
                self?.reportCompactFrame()
            }
        }

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
            switch sheetPresentationController.selectedDetentIdentifier {
            case Self.compactID: presentation.detent = .compact
            case .large: presentation.detent = .large
            default: presentation.detent = .medium
            }
            scheduleCompactFrameReport()
        }

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
            hosting?.presentingViewController?.dismiss(animated: false)
            hosting = nil
        }

    }
}
