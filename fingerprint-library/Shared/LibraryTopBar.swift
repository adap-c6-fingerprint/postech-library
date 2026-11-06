import SwiftUI
import UIKit

/// 화면 제목과 하트·카트·프로필을 함께 배치하는 공통 네이티브 툴바.
struct LibraryTopBar: ToolbarContent {
    let title: String
    var onFavorites: (() -> Void)?
    let onBasket: () -> Void
    var onProfile: (() -> Void)?

    struct Constants {
      static let colorTextTitle: Color = Color(red: 0.98, green: 0.98, blue: 0.98)
      static let FontSize32: CGFloat = 32
      static let FontFamilyPretendard: String = "Pretendard"
    }

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            LibraryTopBarTitle(title: title)
        }
        .sharedBackgroundVisibility(.hidden)
        ToolbarItemGroup(placement: .topBarTrailing) {
            LibraryTopBarButton(title: "관심 도서", symbol: "heart.fill", identifier: "library-top-bar-favorites", action: onFavorites)
            LibraryTopBarButton(title: "책바구니", symbol: "cart.fill", identifier: "library-top-bar-basket", action: onBasket)
        }
        // 하트와 카트는 하나의 시스템 Liquid Glass 배경을 공유한다.
        .sharedBackgroundVisibility(.visible)

        ToolbarSpacer(.fixed, placement: .topBarTrailing)

        ToolbarItem(placement: .topBarTrailing) {
            ProfileSettingsButton(action: onProfile)
        }
        .sharedBackgroundVisibility(.visible)
    }
}

/// 홈·추천·검색 탭의 제목과 버튼을 같은 위치에 배치한다.
struct LibraryTabTopBar: View {
    let title: String
    var onFavorites: (() -> Void)?
    let onBasket: () -> Void
    var onProfile: (() -> Void)?
    var titleAlignment: VerticalAlignment = .center
    var contentHeight: CGFloat? = 54

    var body: some View {
        HStack(alignment: titleAlignment, spacing: 12) {
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
            ProfileSettingsButton(action: onProfile, size: 44)
                .frame(width: 44, height: 44)
                .glassEffect(.regular, in: .circle)
        }
        .font(.system(size: 24))
        .frame(height: contentHeight, alignment: .top)
        .padding(.horizontal, 16)
        .padding(.top, 13)
        .environment(\.colorScheme, .dark)
    }
}

private struct LibraryTopBarTitle: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.custom(LibraryTopBar.Constants.FontFamilyPretendard, size: LibraryTopBar.Constants.FontSize32).weight(.semibold))
            .foregroundStyle(LibraryTopBar.Constants.colorTextTitle)
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

/// 기본 UIKit 블러를 옅게 적용한다. 카메라 이동 시 지도를 캡처하거나 이미지를 교체하지 않는다.
struct LibraryTopBarBackground: View {
    private let height: CGFloat = 361
    private let shade = Color(red: 18.0 / 255, green: 18.0 / 255, blue: 18.0 / 255)

    var body: some View {
        ZStack {
            LibraryTopBarBlur()
            LinearGradient(colors: [shade, shade.opacity(0)], startPoint: .top, endPoint: .bottom)
                .opacity(0.3)
        }
        .frame(height: height)
        .environment(\.colorScheme, .dark)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// 고정된 기본 블러를 직접 마스크로 옅게 합성한다. 전환 중 보간 상태를 유지하지 않는다.
private struct LibraryTopBarBlur: UIViewRepresentable {
    func makeUIView(context: Context) -> BlurView { BlurView() }

    func updateUIView(_ uiView: BlurView, context: Context) {}

    final class BlurView: UIVisualEffectView {
        private let fade = FadeMaskView()

        init() {
            super.init(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
            isUserInteractionEnabled = false
            accessibilityIdentifier = "library-top-bar-blur"
            accessibilityElementsHidden = true
        }

        required init?(coder: NSCoder) { return nil }

        override func layoutSubviews() {
            super.layoutSubviews()
            if fade.frame != bounds {
                mask = nil
                fade.frame = bounds
                mask = fade
            }
        }
    }

    final class FadeMaskView: UIView {
        override class var layerClass: AnyClass { CAGradientLayer.self }

        init() {
            super.init(frame: .zero)
            let gradient = layer as! CAGradientLayer
            let subtle = UIColor.white.withAlphaComponent(0.15).cgColor
            gradient.colors = [subtle, subtle, UIColor.clear.cgColor]
            gradient.locations = [0, 0.85, 1]
            gradient.startPoint = CGPoint(x: 0.5, y: 0)
            gradient.endPoint = CGPoint(x: 0.5, y: 1)
        }

        required init?(coder: NSCoder) { return nil }
    }
}
