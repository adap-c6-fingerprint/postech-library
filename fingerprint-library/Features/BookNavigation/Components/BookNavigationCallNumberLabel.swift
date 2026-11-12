import SwiftUI
import UIKit

/// 책등과 확대 번호표가 같은 세 줄 데이터를 사용하되 각자의 표시 크기에 맞춰 글자를 배치한다.
struct BookNavigationCallNumberLabel: View {
    let callNumber: BookNavigationArrivalCallNumber
    let layout: BookNavigationCallNumberLabelLayout
    var emphasizesFirstLine = true
    // 확대 번호표만 첫 줄(분류+숫자)을 굵게 표시한다

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(layout.lines.enumerated()), id: \.offset) { index, line in
                    Text(line)
                        .font(Font(Self.font(size: layout.fontSize, emphasized: index == 0 && emphasizesFirstLine)))
                        .tracking(layout.tracking)
                        .foregroundStyle(index == 0 && emphasizesFirstLine ? Color.black : Design.textColor)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: layout.lineHeight, alignment: .leading)
                }
            }
            .padding(.horizontal, layout.horizontalPadding)
            .padding(.vertical, layout.verticalPadding)
            .frame(width: layout.size.width, height: layout.upperHeight)
            .background(Design.upperColor)
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: Design.cornerRadius * layout.scale,
                                              topTrailingRadius: Design.cornerRadius * layout.scale))

            Text(classMark)
                .font(.custom("Pretendard-SemiBold", fixedSize: layout.markFontSize))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.01)
                .frame(width: layout.size.width, height: layout.lowerHeight)
                .background(Design.lowerColor)
                .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: Design.cornerRadius * layout.scale,
                                                  bottomTrailingRadius: Design.cornerRadius * layout.scale))
        }
        .frame(width: layout.size.width, height: layout.size.height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("청구기호 \(callNumber.rawValue)")
    }

    static func enlargedLayout(for number: BookNavigationArrivalCallNumber, maximumWidth: CGFloat) -> BookNavigationCallNumberLabelLayout {
        .init(callNumber: number, maximumWidth: maximumWidth) { text, size, first in
            textWidth(text, fontSize: size, emphasized: first)
        }
    }

    static func spineLayout(from layout: BookNavigationCallNumberLabelLayout, size: CGSize) -> BookNavigationCallNumberLabelLayout {
        layout.fitted(to: size) { text, fontSize, _ in
            textWidth(text, fontSize: fontSize, emphasized: false)
        }
    }

    private static func font(size: CGFloat, emphasized: Bool) -> UIFont {
        UIFont(name: emphasized ? "Pretendard-Bold" : "Pretendard-Medium", size: size)
            ?? .systemFont(ofSize: size, weight: emphasized ? .bold : .medium)
    }

    private static func textWidth(_ text: String, fontSize: CGFloat, emphasized: Bool) -> CGFloat {
        (text as NSString).size(withAttributes: [
            .font: font(size: fontSize, emphasized: emphasized),
            .kern: BookNavigationCallNumberLabelLayout.tracking(for: fontSize)
        ]).width + min(0.5, fontSize / 40)
    }

    private var classMark: String { String(callNumber.classification.prefix(1)).uppercased() }
    // 파란 칸에는 분류기호의 첫 글자를 적는다 (PR → P)

    enum Design {
        static let cornerRadius: CGFloat = 4.679
        static let upperColor = Color(red: 0xD9 / 255, green: 0xD9 / 255, blue: 0xD9 / 255)
        static let textColor = Color(red: 0x40 / 255, green: 0x40 / 255, blue: 0x40 / 255)
        static let lowerColor = Color(red: 0x4D / 255, green: 0x71 / 255, blue: 0xFF / 255)
    }
}
