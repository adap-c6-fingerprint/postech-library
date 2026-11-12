import SwiftUI

/// 경로 미리보기와 길안내에서 사용하는 층 표시.
struct IndoorMapFloorBadge: View {
    let floor: IndoorMapFloor
    var isCurrent: Bool = false

    var body: some View {
        Text(isCurrent ? "현재 \(floor.ordinal + 1)F" : "\(floor.ordinal + 1)F")
            .typography(.caption2)
            .foregroundStyle(PobookUI.ColorToken.neutralPrimary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(minWidth: 61, minHeight: 34)
            .glassEffect(.regular, in: .rect(cornerRadius: 12))
            .accessibilityLabel(isCurrent ? "현재 \(floor.name)" : floor.name)
    }
}
