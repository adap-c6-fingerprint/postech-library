import SwiftUI

/// 홈·추천·검색 탭의 공용 상단 바.
/// 시스템 내비게이션 바의 큰 제목과 툴바 아이템을 그대로 사용한다.
struct LibraryTabToolbar: ViewModifier {
    let title: String
    let onFavorites: () -> Void
    let onCart: () -> Void
    let onProfile: () -> Void

    func body(content: Content) -> some View {
        content
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("내가 읽고 싶은 책", systemImage: "bookmark.fill", action: onFavorites)
                        .accessibilityIdentifier("library-top-bar-favorites")
                    Button("책바구니", systemImage: "cart.fill", action: onCart)
                        .accessibilityIdentifier("library-top-bar-cart")
                }
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
                ToolbarItem(placement: .topBarTrailing) {
                    Button("마이페이지", systemImage: "person.fill", action: onProfile)
                        .accessibilityIdentifier("library-top-bar-profile")
                }
            }
    }
}

extension View {
    func libraryTabToolbar(
        title: String,
        onFavorites: @escaping () -> Void,
        onCart: @escaping () -> Void,
        onProfile: @escaping () -> Void
    ) -> some View {
        modifier(LibraryTabToolbar(title: title, onFavorites: onFavorites, onCart: onCart, onProfile: onProfile))
    }
}

struct LibraryTopBarButton: View {
    let title: String
    let symbol: String
    let identifier: String
    let action: (() -> Void)?
    var size: CGFloat?

    var body: some View {
        Button(action: action ?? {}) {
            Label(title, systemImage: symbol).labelStyle(.iconOnly)
                .frame(width: size, height: size)
                .contentShape(.rect)
        }
        .buttonStyle(LibraryTopBarSymbolStyle())
        .tint(.white)
        .disabled(action == nil)
        .accessibilityIdentifier(identifier)
    }
}

private struct LibraryTopBarSymbolStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

struct LibraryTopBarBackground: View {
    private let height: CGFloat = 361
    private let shade = Color(red: 18.0 / 255, green: 18.0 / 255, blue: 18.0 / 255)

    var body: some View {
        ZStack {
            LibraryTopBarBlur()

            LinearGradient(
                stops: [
                    .init(color: shade, location: 0),
                    .init(color: shade, location: 0.65),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .opacity(0.3)
        }
        .frame(height: height)
        .environment(\.colorScheme, .dark)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct LibraryTopBarBlur: View {
    var body: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .white, location: 0),
                        .init(color: .white, location: 0.15),
                        .init(color: .white, location: 0.25),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
    }
}
