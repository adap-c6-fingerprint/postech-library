import SwiftUI

/// 화면 제목과 하트·카트·프로필을 함께 배치하는 공통 네이티브 툴바.
struct LibraryTopBar: ToolbarContent {
    let title: String
    var onFavorites: (() -> Void)?
    let onBasket: () -> Void
    var onProfile: (() -> Void)?

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Text(title)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.white)
                .fixedSize()
                .accessibilityIdentifier("library-top-bar-title")
        }
        .sharedBackgroundVisibility(.hidden)
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button(action: onFavorites ?? {}) {
                Label("관심 도서", systemImage: "heart.fill").labelStyle(.iconOnly)
            }
            .buttonStyle(LibraryTopBarSymbolStyle())
            .tint(.white)
            .disabled(onFavorites == nil)
            .accessibilityIdentifier("library-top-bar-favorites")

            Button(action: onBasket) {
                Label("책바구니", systemImage: "cart.fill").labelStyle(.iconOnly)
            }
            .buttonStyle(LibraryTopBarSymbolStyle())
            .tint(.white)
            .accessibilityIdentifier("library-top-bar-basket")
        }
        .sharedBackgroundVisibility(.visible)

        ToolbarSpacer(.fixed, placement: .topBarTrailing)

        ToolbarItem(placement: .topBarTrailing) {
            Button(action: onProfile ?? {}) {
                Label("마이페이지", systemImage: "person.fill").labelStyle(.iconOnly)
            }
            .buttonStyle(LibraryTopBarSymbolStyle())
            .tint(.white)
            .disabled(onProfile == nil)
            .accessibilityIdentifier("library-top-bar-profile")
        }
    }
}

/// 비활성 여부는 Button이 관리하고, 심볼 색상은 디자인에 맞게 흰색으로 유지한다.
private struct LibraryTopBarSymbolStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// 지도를 상단 메뉴 뒤까지 표시하면서, 위쪽의 블러와 명암을 아래로 서서히 없앤다.
struct LibraryTopBarBackground: View {
    var body: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .overlay {
                LinearGradient(
                    stops: [.init(color: .black.opacity(0.9), location: 0),
                            .init(color: .black.opacity(0.6), location: 0.55),
                            .init(color: .clear, location: 1)],
                    startPoint: .top, endPoint: .bottom
                )
            }
            .mask {
                LinearGradient(colors: [.black, .black, .clear], startPoint: .top, endPoint: .bottom)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
