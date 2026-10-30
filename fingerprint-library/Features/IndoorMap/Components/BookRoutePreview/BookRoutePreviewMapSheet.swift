import SwiftUI

/// 미리보기 전용 배치. 지도는 전체 화면을 유지하고 네이티브 시트가 가리는 높이만 전달한다.
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
                // MapKit은 자체 safe area를 더하므로 중복 여백을 제외한다.
                map(.init(top: 60, left: 0, bottom: max(0, sheetHeight - geometry.safeAreaInsets.bottom), right: 0), cameraRevision)
                    .ignoresSafeArea()
                Button {
                    if isPresented {
                        isLeaving = true
                        isPresented = false
                    } else { onBack() }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.headline)
                        .frame(width: 44, height: 44)
                        .background(.regularMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .tint(.white)
                .padding(16)
                .accessibilityLabel("뒤로가기")
                .accessibilityIdentifier("book-route-preview-back")
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
