import SwiftUI
import UIKit

/// 홈·추천·검색 탭의 제목과 버튼을 같은 위치에 배치한다.
struct LibraryTabTopBar: View {
    let title: String
    let onFavorites: () -> Void
    let onBasket: () -> Void
    let onProfile: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
        // 추천 탭 기준: 제목 아래쪽을 버튼 아래쪽에 맞춘다. 홈도 같은 배치를 쓴다.
            LibraryTopBarTitle(title: title)
                .padding(.leading, 4)
            Spacer(minLength: 12)
            HStack(spacing: 8) {
                LibraryTopBarButton(title: "관심 도서", symbol: "heart.fill", identifier: "library-top-bar-favorites", action: onFavorites, size: 44)
                    .frame(width: 44, height: 44)
                LibraryTopBarButton(title: "책바구니", symbol: "cart.fill", identifier: "library-top-bar-basket", action: onBasket, size: 44)
                    .frame(width: 44, height: 44)
            }
            .glassEffect(.regular.interactive(), in: .capsule)
            LibraryTopBarButton(title: "마이페이지", symbol: "person.fill", identifier: "library-top-bar-profile", action: onProfile, size: 44)
            // 찜·책바구니 버튼처럼 누르는 즉시 이동한다. 데이터 수집 설정은 마이페이지 설정 목록의 행으로 연다.
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
            .foregroundStyle(DS.ColorToken.neutralPrimary)
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

/// 비활성 여부는 Button이 관리하고, 심볼 색상은 디자인에 맞게 흰색으로 유지한다.
private struct LibraryTopBarSymbolStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// Material 블러를 상단에 표시하고 아래쪽 경계에서 서서히 사라지게 한다.
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
