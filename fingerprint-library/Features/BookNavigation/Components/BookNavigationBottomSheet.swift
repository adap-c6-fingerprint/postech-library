import SwiftUI

struct BookNavigationBottomSheet<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var isExpanded: Bool
    let height: CGFloat
    let bottomInset: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            Button { setExpanded(!isExpanded) } label: {
                Capsule().fill(.white.opacity(0.3))
                    .frame(width: 36, height: 5)
                    .frame(maxWidth: .infinity).frame(height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isExpanded ? "길안내 시트 접기" : "길안내 시트 펼치기")
            .accessibilityIdentifier("book-navigation-sheet-toggle")
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(.bottom, bottomInset)
        .frame(maxWidth: .infinity).frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .glassEffect(.regular.tint(.black.opacity(0.45)), in: RoundedRectangle(cornerRadius: 28))
        .contentShape(Rectangle())
        .simultaneousGesture(DragGesture(minimumDistance: 12).onEnded { value in
            let travel = value.predictedEndTranslation.height
            if abs(travel) > 24 { setExpanded(travel < 0) }
        })
        .accessibilityIdentifier("book-navigation-sheet")
    }

    private func setExpanded(_ expanded: Bool) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { isExpanded = expanded }
    }
}
