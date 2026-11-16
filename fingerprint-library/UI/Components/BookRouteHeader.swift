import SwiftUI

/// 길안내와 출발 위치 선택 화면의 공통 헤더.
struct BookRouteHeader: View {
    struct Accessory {
        let systemImage: String
        let tint: Color
        let accessibilityLabel: String
        let accessibilityIdentifier: String
        let action: () -> Void
    }

    let title: String
    let subtitle: String?
    let closeLabel: String
    var accessory: Accessory? = nil
    var accessibilityHint: String = ""
    var titleIdentifier: String = "book-route-header-title"
    var subtitleIdentifier: String = "book-route-header-subtitle"
    var closeIdentifier: String = "book-route-header-close"
    let onClose: () -> Void

    private let closeButtonSize: CGFloat = 44

    private var trailingButtonsWidth: CGFloat {
        accessory == nil ? closeButtonSize : closeButtonSize * 2 + PobookUI.Spacing._8
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PobookUI.Spacing._4) {
            Text(title)
                .typography(.title1)
                .foregroundStyle(PobookUI.ColorToken.neutralPrimary)
                .lineLimit(2)
                .padding(.trailing, trailingButtonsWidth + PobookUI.Spacing._16)
                .accessibilityIdentifier(titleIdentifier)
            if let subtitle {
                Text(subtitle)
                    .typography(.title1)
                    .foregroundStyle(PobookUI.ColorToken.neutralTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(subtitleIdentifier)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint(accessibilityHint)
        .frame(maxWidth: .infinity, minHeight: closeButtonSize, alignment: .topLeading)
        .overlay(alignment: .topTrailing) {
            HStack(spacing: PobookUI.Spacing._8) {
                if let accessory {
                    Button(action: accessory.action) {
                        Image(systemName: accessory.systemImage)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(accessory.tint)
                            .frame(width: closeButtonSize, height: closeButtonSize)
                            .glassEffect(.regular.interactive(), in: .circle)
                    }
                    .accessibilityLabel(accessory.accessibilityLabel)
                    .accessibilityIdentifier(accessory.accessibilityIdentifier)
                }
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: closeButtonSize, height: closeButtonSize)
                        .glassEffect(.regular.interactive(), in: .circle)
                }
                .accessibilityLabel(closeLabel)
                .accessibilityIdentifier(closeIdentifier)
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(PobookUI.ColorToken.neutralPrimary)
        .padding(.horizontal, PobookUI.Spacing._20)
        .padding(.top, PobookUI.Spacing._20)
    }
}

#if DEBUG
#Preview("공통 경로 헤더 · 단권") {
    BookRouteHeader(
        title: "푸울에 풍덩푸울에 풍덩푸울에 풍덩",
        subtitle: "4층 337번 서가",
        closeLabel: "안내 종료", onClose: {})
        .frame(maxHeight: .infinity, alignment: .top)
        .background(PobookUI.ColorToken.neutralDark)
        .preferredColorScheme(.dark)
}

#Preview("공통 경로 헤더 · 다권") {
    BookRouteHeader(
        title: "출발지 직접 설정하기",
        subtitle: "층을 선택하고 지도를 움직여\n출발지를 직접 설정해주세요",
        closeLabel: "출발 위치 직접 설정 그만두기", onClose: {})
        .frame(maxHeight: .infinity, alignment: .top)
        .background(PobookUI.ColorToken.neutralDark)
        .preferredColorScheme(.dark)
}

#Preview("공통 경로 헤더 · 큰 글자") {
    BookRouteHeader(
        title: "출발지 직접 설정하기",
        subtitle: "층을 선택하고 지도를 움직여\n출발지를 직접 설정해주세요",
        closeLabel: "출발 위치 직접 설정 그만두기", onClose: {})
        .frame(maxHeight: .infinity, alignment: .top)
        .background(PobookUI.ColorToken.neutralDark)
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility3)
}
#endif
