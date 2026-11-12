import SwiftUI

/// 책 페이지의 가로 넘기기와 설명 스크롤을 유지하는 두 단계 미리보기 패널.
struct BookRoutePreviewBooksPanel<Content: View>: View {
    @Binding var presentation: BookRoutePreviewPanelState
    let collapsedHeight: CGFloat
    let maximumHeight: CGFloat
    var identifier = "multiBookPreview.panel"
    @ViewBuilder let content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @GestureState private var isGestureActive = false
    @State private var dragHeight: CGFloat?
    @State private var dragStartHeight: CGFloat?
    @State private var dragStartTranslation: CGFloat = 0
    @State private var renderedHeight: CGFloat = 0
    @State private var isSettling = false
    @State private var motionID = UUID()

    private var minimumHeight: CGFloat { min(collapsedHeight, maximumHeight) }
    private var height: CGFloat {
        dragHeight ?? (presentation.isExpanded ? maximumHeight : minimumHeight)
    }
    private var cornerRadius: CGFloat { 28 * (1 - presentation.expansionProgress) }

    var body: some View {
        content()
            .frame(height: height)
            .background {
                Color.clear
                    .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
                    .opacity(1 - presentation.expansionProgress)
            }
            .clipShape(.rect(cornerRadius: cornerRadius))
            .contentShape(.rect)
            .simultaneousGesture(panelDrag)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { renderedHeight = $0 }
            .onChange(of: isGestureActive) { _, active in
                guard !active else { return }
                let id = motionID
                Task { @MainActor in
                    await Task.yield()
                    guard motionID == id, !isGestureActive,
                          dragStartHeight != nil, !isSettling else { return }
                    settle(expanded: presentation.isExpanded)
                }
            }
            .onDisappear {
                motionID = UUID()
                presentation.isMoving = false
                presentation.dragProgress = nil
            }
            .accessibilityIdentifier(identifier)
            .accessibilityAction(named: Text("책 소개 펼치기")) { settle(expanded: true) }
            .accessibilityAction(named: Text("책 소개 접기")) { settle(expanded: false) }
    }

    private var panelDrag: some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .global)
            .updating($isGestureActive) { _, active, _ in active = true }
            .onChanged { value in
                if dragStartHeight == nil {
                    guard presentation.canBeginDrag(translation: value.translation) else { return }
                    motionID = UUID()
                    isSettling = false
                    presentation.isMoving = true
                    dragStartHeight = renderedHeight > 0 ? renderedHeight : height
                    dragStartTranslation = value.translation.height
                }
                guard let start = dragStartHeight else { return }
                let translation = value.translation.height - dragStartTranslation
                dragHeight = min(maximumHeight, max(minimumHeight, start - translation))
                presentation.dragProgress = BookPreviewSheetLayout.progress(
                    height: dragHeight ?? minimumHeight, minimum: minimumHeight,
                    maximum: maximumHeight, isExpanded: presentation.isExpanded)
            }
            .onEnded { value in
                guard dragStartHeight != nil else { return }
                settle(expanded: presentation.targetIsExpanded(
                    translation: value.translation.height - dragStartTranslation,
                    predictedTranslation: value.predictedEndTranslation.height - dragStartTranslation))
            }
    }

    private func settle(expanded: Bool) {
        let id = UUID()
        motionID = id
        isSettling = true
        presentation.isMoving = true
        dragStartHeight = nil
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.3), completionCriteria: .removed) {
            presentation.isExpanded = expanded
            presentation.dragProgress = nil
            dragHeight = nil
        } completion: {
            guard motionID == id else { return }
            isSettling = false
            presentation.isMoving = false
        }
    }
}
