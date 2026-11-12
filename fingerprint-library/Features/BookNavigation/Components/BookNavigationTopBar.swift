import SwiftUI

struct BookNavigationTopBar: View {
    let backLabel: String
    let backIdentifier: String
    let onBack: () -> Void

    var body: some View {
        HStack {
            LibraryBackButton(title: backLabel, identifier: backIdentifier, action: onBack)
            Spacer()
        }
        .frame(height: 48)
    }
}

#if DEBUG
#Preview("책 찾기 상단바") {
    BookNavigationTopBar(
        backLabel: "길안내로 돌아가기",
        backIdentifier: "preview.navigation.back",
        onBack: {}
    )
    .padding(.horizontal, 16)
    .background(Color.backgroundDefault)
    .preferredColorScheme(.dark)
}
#endif
