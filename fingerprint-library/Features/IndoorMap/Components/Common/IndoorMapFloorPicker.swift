import SwiftUI

/// 지도 화면들이 함께 쓰는 층 선택 버튼.
///
/// ``IndoorMapView``의 층 선택 UI를 그대로 옮겨 Store 없이도 쓸 수 있게 했다.
/// 출발지 직접 설정처럼 지도 Store가 없는 화면에서도 같은 모양·치수를 유지한다.
struct IndoorMapFloorPicker: View {
    let floors: [IndoorMapFloor]
    let selectedFloorID: UUID?
    var appearance: IndoorMapKitView.Appearance = .standard
    /// 선택한 층을 "현재 NF"로 표시한다. 선택이 곧 사용자의 현재 층인 화면에서 사용한다.
    var marksSelectionAsCurrent = false
    let onSelect: (UUID) -> Void

    private var isHome: Bool { appearance == .home }

    /// 남은 높이에 세로 목록이 들어가지 않으면 가로로 펼쳐 스크롤 없이 모든 층을 표시한다.
    var body: some View {
        let height = CGFloat(floors.count) * 34
        ViewThatFits(in: .vertical) {
            VStack(alignment: .leading, spacing: 0) {
                floorButtons
            }
            .padding(0)
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .topLeading)
            .frame(width: isHome ? 61 : 56)
            HStack(spacing: 0) {
                floorButtons
            }
            .fixedSize()
        }
        .background(isHome ? .clear : Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: PobookUI.Radius.floorAmenitiesToggle))
        .glassEffect(isHome ? .regular : .identity, in: .rect(cornerRadius: PobookUI.Radius.floorAmenitiesToggle))
        .overlay {
            GeometryReader { geometry in
                if floors.count > 1 {
                    Path { path in
                        let size = geometry.size
                        let horizontal = size.width > size.height
                        for index in 1..<floors.count {
                            let fraction = CGFloat(index) / CGFloat(floors.count)
                            if horizontal {
                                let x = size.width * fraction
                                path.move(to: CGPoint(x: x, y: 0))
                                path.addLine(to: CGPoint(x: x, y: size.height))
                            } else {
                                let y = size.height * fraction
                                path.move(to: CGPoint(x: 0, y: y))
                                path.addLine(to: CGPoint(x: size.width, y: y))
                            }
                        }
                    }
                    .stroke(isHome ? Color.white.opacity(0.35) : Color(uiColor: .separator), lineWidth: 1)
                }
            }
            .allowsHitTesting(false)
        }
        .overlay(
            RoundedRectangle(cornerRadius: PobookUI.Radius.floorAmenitiesToggle)
                .strokeBorder(Color(uiColor: .separator).opacity(0.6))
        )
        .shadow(color: .black.opacity(0.1), radius: 2.5, x: 1, y: 1)
    }

    /// 세로·가로 배치 모두 34pt 높이와 같은 글자 여백을 사용한다.
    private var floorButtons: some View {
        let buttonWidth: CGFloat
        let selectedBackground: Color
        let selectedText: Color
        let unselectedText: Color

        // 홈 지도에는 F 표기와 디자인 토큰을, 일반 지도에는 층 이름과 시스템 테마를 사용한다.
        switch appearance {
        case .home:
            buttonWidth = 61
            selectedBackground = PobookUI.ColorToken.primaryLight
            selectedText = PobookUI.ColorToken.neutralDark
            unselectedText = PobookUI.ColorToken.neutralPrimary
        case .standard, .bookDetail:
            buttonWidth = 56
            selectedBackground = Color(uiColor: .label)
            selectedText = Color(uiColor: .systemBackground)
            unselectedText = .primary
        }

        return ForEach(floors.reversed()) { item in
            let isSelected = item.id == selectedFloorID
            Button {
                onSelect(item.id)
            } label: {
                label(title(for: item, isSelected: isSelected), isSelected: isSelected)
                    .frame(width: buttonWidth, height: 34)
                    .background(isSelected ? selectedBackground : .clear)
                    .foregroundStyle(isSelected ? selectedText : unselectedText)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityLabel(for: item, isSelected: isSelected))
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            .accessibilityIdentifier("floor-\(item.ordinal)")
        }
    }

    /// "현재 4F"는 기존 층 이름보다 길다. 좌우 16 여백을 쓰면 글자가 잘리므로 시안의 44×20 글자 영역을 쓴다.
    @ViewBuilder
    private func label(_ text: String, isSelected: Bool) -> some View {
        let base = Text(text)
            .typography(isSelected ? .caption1.weight(.semibold) : .caption1)
            .multilineTextAlignment(.center)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .allowsTightening(true)
        if marksSelectionAsCurrent {
            base.frame(width: 44, height: 20)
        } else {
            base
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 10)
                .padding(.horizontal, PobookUI.Spacing._16)
        }
    }

    private func title(for floor: IndoorMapFloor, isSelected: Bool) -> String {
        if marksSelectionAsCurrent, isSelected { return "현재 \(floor.ordinal + 1)F" }
        return appearance == .home || marksSelectionAsCurrent ? "\(floor.ordinal + 1)F" : floor.name
    }

    private func accessibilityLabel(for floor: IndoorMapFloor, isSelected: Bool) -> String {
        if marksSelectionAsCurrent {
            return isSelected ? "현재 \(floor.name)" : "\(floor.name)을 현재 층으로 선택"
        }
        return "\(floor.name) 지도 보기"
    }
}
