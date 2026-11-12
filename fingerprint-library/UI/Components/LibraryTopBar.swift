import SwiftUI
import UIKit

struct LibraryTabTopBar: View {
    let title: String
    let onFavorites: () -> Void
    let onCart: () -> Void
    let onProfile: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            LibraryTopBarTitle(title: title)
                .padding(.leading, 4)
            Spacer(minLength: 12)
            HStack(spacing: 8) {
                LibraryTopBarButton(title: "내가 읽고 싶은 책", symbol: "bookmark.fill", identifier: "library-top-bar-favorites", action: onFavorites, size: 44)
                    .frame(width: 44, height: 44)
                LibraryTopBarButton(title: "책바구니", symbol: "cart.fill", identifier: "library-top-bar-cart", action: onCart, size: 44)
                    .frame(width: 44, height: 44)
            }
            .glassEffect(.regular.interactive(), in: .capsule)
            LibraryTopBarButton(title: "마이페이지", symbol: "person.fill", identifier: "library-top-bar-profile", action: onProfile, size: 44)
                .frame(width: 44, height: 44)
                .glassEffect(.regular, in: .circle)
        }
        .font(.system(size: 24))
        .padding(.horizontal, 16)
        .padding(.top, 13)
        .environment(\.colorScheme, .dark)
    }
}

private struct LibraryTopBarTitle: View {
    let title: String

    var body: some View {
        Text(title)
            .typography(.largeTitle)
            .foregroundStyle(PobookUI.ColorToken.neutralPrimary)
            .fixedSize()
            .accessibilityIdentifier("library-top-bar-title")
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
