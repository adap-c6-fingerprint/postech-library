import SwiftUI

struct LibraryBackButton: View {
    var title = "뒤로가기"
    let identifier: String
    let action: (() -> Void)?
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        LibraryTopBarButton(
            title: title,
            symbol: "chevron.left",
            identifier: identifier,
            action: action,
            size: 44
        )
        .font(.system(size: 22, weight: .regular))
        .glassEffect(.regular.interactive(), in: .circle)
        .disabled(action == nil)
        .opacity(isEnabled && action != nil ? 1 : 0.4)
    }
}

#if DEBUG
#Preview("뒤로가기 · 활성 / 비활성") {
    HStack(spacing: 24) {
        LibraryBackButton(identifier: "preview.back", action: {})
        LibraryBackButton(title: "길안내로 돌아가기", identifier: "preview.back.disabled", action: nil)
    }
    .padding(24)
    .background(Color.backgroundDefault)
    .preferredColorScheme(.dark)
}
#endif
