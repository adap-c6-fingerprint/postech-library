import SwiftUI

/// 책등 아래쪽에 붙은 청구기호 번호표. 확대 표시와 책등 위 작은 표시가 같은 모양을 배율만 달리해 쓴다.
struct BookNavigationCallNumberLabel: View {
    let callNumber: BookNavigationArrivalCallNumber
    let width: CGFloat
    let scale: CGFloat
    // 피그마 확대 번호표(105 × 212) 기준 배율
    var emphasizesFirstLine = true
    // 확대 번호표만 첫 줄(분류+숫자)을 굵게 표시한다

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                    Text(line)
                        .font(.custom(index == 0 && emphasizesFirstLine ? "Pretendard-Bold" : "Pretendard-Medium",
                                      fixedSize: Design.fontSize * scale))
                        .tracking(Design.tracking * scale)
                        .foregroundStyle(index == 0 && emphasizesFirstLine ? Color.black : Design.textColor)
                        .frame(height: Design.fontSize * Design.lineHeight * scale, alignment: .leading)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
            }
            .padding(.vertical, Design.textVerticalPadding * scale)
            .frame(width: width, height: Design.upperHeight * scale)
            .background(Design.upperColor)
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: Design.cornerRadius * scale,
                                              topTrailingRadius: Design.cornerRadius * scale))

            Text(classMark)
                .font(.custom("Pretendard-SemiBold", fixedSize: Design.markFontSize * scale))
                .foregroundStyle(.white)
                .frame(width: width, height: Design.lowerHeight * scale)
                .background(Design.lowerColor)
                .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: Design.cornerRadius * scale,
                                                  bottomTrailingRadius: Design.cornerRadius * scale))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("청구기호 \(callNumber.rawValue)")
    }

    private var lines: [String] {
        let first: String = callNumber.classification + callNumber.number
        let rest: [String] = callNumber.suffix.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        return [first] + rest
    }
    // 예: "PR2993 .F2 .P45" → PR2993 / .F2 / .P45

    private var classMark: String { String(callNumber.classification.prefix(1)).uppercased() }
    // 파란 칸에는 분류기호의 첫 글자를 적는다 (PR → P)

    enum Design {
        static let width: CGFloat = 105
        static let upperHeight: CGFloat = 149.977
        static let lowerHeight: CGFloat = 61.755
        static var height: CGFloat { upperHeight + lowerHeight }
        static let cornerRadius: CGFloat = 4.679
        static let textVerticalPadding: CGFloat = 33.163
        static let fontSize: CGFloat = 20.977
        static let lineHeight: CGFloat = 1.3
        static let tracking: CGFloat = -0.7188
        static let markFontSize: CGFloat = 50.308
        static let upperColor = Color(red: 0xD9 / 255, green: 0xD9 / 255, blue: 0xD9 / 255)
        static let textColor = Color(red: 0x40 / 255, green: 0x40 / 255, blue: 0x40 / 255)
        static let lowerColor = Color(red: 0x4D / 255, green: 0x71 / 255, blue: 0xFF / 255)
    }
}
