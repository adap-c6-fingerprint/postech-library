import ComposableArchitecture
import SwiftUI

private struct BookDetailCartPresentation: ViewModifier {
    @Bindable var store: StoreOf<BookDetailFeature>

    private var cartNoticeTitle: String {
        store.cartNotice == .alreadyAdded ? "이미 책바구니에 담긴 책이에요." : "책이 책바구니에 담겼어요."
    }

    private var cartNotice: Binding<BookDetailFeature.CartNotice?> {
        Binding(
            get: { store.cartNotice },
            set: { notice in
                if notice == nil, store.cartNotice != nil {
                    store.send(.cartNoticeDismissed)
                }
            }
        )
    }

    func body(content: Content) -> some View {
        content
            .fullScreenCover(item: $store.scope(state: \.cart, action: \.cart)) { cartStore in
                NavigationStack {
                    BookCartView(store: cartStore, onClose: { store.send(.cart(.dismiss)) })
                }
            }
            .alert(cartNoticeTitle, item: cartNotice) { _ in
                Button("나중에", role: .cancel) {}
                Button("바로가기") { store.send(.cartShortcutTapped) }
                    .keyboardShortcut(.defaultAction)
            } message: { _ in
                Text("책바구니로 이동하여 책의 경로를 확인하시겠습니까?")
            }
            .cartLimitAlert(isPresented: store.isCartLimitAlertPresented) {
                store.send(.cartLimitAlertDismissed)
            }
    }
}

extension View {
    func bookDetailCartPresentation(store: StoreOf<BookDetailFeature>) -> some View {
        modifier(BookDetailCartPresentation(store: store))
    }
}
