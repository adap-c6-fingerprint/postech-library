import SwiftUI

/// 책 미리보기의 시트 크기·여백·전체 화면 전환을 구성한다.
struct BookPreviewSheet<Content: View, Actions: View, ExpandedBackground: View>: View {
    @Binding var presentation: BookRoutePreviewPanelState
    let floor: IndoorMapFloor?
    let availableSize: CGSize
    let safeAreaInsets: EdgeInsets
    let topBarHeight: CGFloat
    let identifierPrefix: String
    let onCoveredHeightChange: (CGFloat) -> Void
    @ViewBuilder let content: () -> Content
    @ViewBuilder let actions: () -> Actions
    @ViewBuilder let expandedBackground: () -> ExpandedBackground

    @State private var actionsHeight: CGFloat = 50
    @State private var renderedHeight: CGFloat = 0

    private var progress: CGFloat { presentation.expansionProgress }
    private var expandedTopInset: CGFloat { safeAreaInsets.top + topBarHeight + 16 }
    private var maximumPanelHeight: CGFloat {
        max(1, availableSize.height - expandedTopInset - actionsHeight - 28 - safeAreaInsets.bottom)
    }

    var body: some View {
        VStack(spacing: 12) {
            if !presentation.showsFullDescription, let floor {
                IndoorMapFloorBadge(floor: floor)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .accessibilityLabel("책 위치 \(floor.name)")
                    .accessibilityIdentifier("\(identifierPrefix).floor")
                    .padding(.bottom, 4)
                    .padding(.leading, 16 + safeAreaInsets.leading)
                    .padding(.trailing, 16 + safeAreaInsets.trailing)
            }
            BookRoutePreviewBooksPanel(
                presentation: $presentation,
                // 표지 186 + 소개 간격 28 + 저자·설명 129.2 + 상하 여백 32.
                collapsedHeight: BookPreviewSheetLayout.collapsedCardHeight,
                maximumHeight: maximumPanelHeight,
                identifier: "\(identifierPrefix).panel"
            ) {
                content()
                    .padding(.leading, safeAreaInsets.leading * progress)
                    .padding(.trailing, safeAreaInsets.trailing * progress)
            }
            .padding(.leading, (16 + safeAreaInsets.leading) * (1 - progress))
            .padding(.trailing, (16 + safeAreaInsets.trailing) * (1 - progress))
            .padding(.top, expandedTopInset * progress)
            actions()
                .padding(.leading, 16 + safeAreaInsets.leading)
                .padding(.trailing, 16 + safeAreaInsets.trailing)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { actionsHeight = $0 }
        }
        .padding(.bottom, 16 + safeAreaInsets.bottom)
        .frame(width: availableSize.width)
        .background { expandedBackground().opacity(progress) }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
            renderedHeight = max(0, height - safeAreaInsets.bottom)
            // 패널을 드래그하는 동안 매 프레임 지도의 서가 초점을 다시 맞추지 않는다.
            if !presentation.showsFullDescription { onCoveredHeightChange(renderedHeight) }
        }
        .onChange(of: presentation.showsFullDescription) { _, showsFullDescription in
            if !showsFullDescription { onCoveredHeightChange(renderedHeight) }
        }
    }
}
