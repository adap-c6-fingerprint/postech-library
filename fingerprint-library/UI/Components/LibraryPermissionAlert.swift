import SwiftUI

struct LibraryPermissionAlert: View {
    let title: String
    let message: String
    var cancelTitle = "동의 안함"
    var confirmTitle = "설정으로 이동"
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .accessibilityHidden(true)
            card
        }
        .accessibilityAddTraits(.isModal)
        .accessibilityIdentifier("library-permission-alert")
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .typography(.body1)
                .foregroundStyle(PobookUI.ColorToken.neutralDark)
                .accessibilityAddTraits(.isHeader)
            Text(message)
                .typography(.caption1)
                .foregroundStyle(PobookUI.ColorToken.neutralDark)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                button(cancelTitle, background: Color(white: 0.76), action: onCancel)
                    .accessibilityIdentifier("library-permission-alert-cancel")
                button(confirmTitle, background: PobookUI.ColorToken.primaryLight, action: onConfirm)
                    .accessibilityIdentifier("library-permission-alert-confirm")
            }
            .padding(.top, 8)
        }
        .padding(20)
        .frame(width: 274)
        .background(Color(white: 0.87), in: RoundedRectangle(cornerRadius: 28))
        .shadow(color: .black.opacity(0.25), radius: 20, y: 8)
    }

    private func button(_ title: String, background: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .typography(.caption1.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(PobookUI.ColorToken.neutralDark)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(background, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
