import SwiftUI

struct BookRoutePreviewMapSheet<MapContent: View, Details: View>: View {
    let onBack: () -> Void
    let onViewportChange: () -> Void
    @ViewBuilder let map: (UIEdgeInsets, Int) -> MapContent
    @ViewBuilder let details: () -> Details
    @State private var isPresented = false
    @State private var isLeaving = false
    @State private var sheetHeight: CGFloat = 0
    @State private var cameraRevision = 0
    @State private var detent: PresentationDetent = .medium

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                map(.init(top: 60, left: 0, bottom: max(0, sheetHeight - geometry.safeAreaInsets.bottom), right: 0), cameraRevision)
                    .ignoresSafeArea()
                LibraryBackButton(identifier: "book-route-preview-back") {
                    if isPresented {
                        isLeaving = true
                        isPresented = false
                    } else { onBack() }
                }
                .padding(16)
            }
            .sheet(isPresented: $isPresented, onDismiss: { if isLeaving { onBack() } }) {
                details()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height + $0.safeAreaInsets.bottom } action: { height in
                        guard height > 0, abs(height - sheetHeight) > 0.5 else { return }
                        sheetHeight = height
                        cameraRevision += 1
                        onViewportChange()
                    }
                    .presentationDetents([.fraction(0.3), .medium, .custom(PreviewExpandedDetent.self)], selection: $detent)
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(28)
                    .presentationBackground(Color(uiColor: .secondarySystemBackground))
                    .presentationBackgroundInteraction(.enabled)
                    .presentationContentInteraction(.resizes)
                    .presentationCompactAdaptation(.none)
                    .interactiveDismissDisabled()
                    .preferredColorScheme(.dark)
            }
            .onGeometryChange(for: CGSize.self) { $0.size } action: { _ in
                cameraRevision += 1
                onViewportChange()
            }
            .onAppear { isPresented = true }
        }
    }
}

private struct PreviewExpandedDetent: CustomPresentationDetent {
    static func height(in context: Context) -> CGFloat? {
        context.maxDetentValue * (context.maxDetentValue < 500 ? 0.6 : 0.72)
    }
}
