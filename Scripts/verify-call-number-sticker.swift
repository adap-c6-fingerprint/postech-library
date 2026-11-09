import Foundation
import CoreGraphics

@main
struct VerifyCallNumberSticker {
    static func main() {
        let examples = [
            "QA76.73 .P98 .V38 2020", "PR2993 .F2 .P45", "TR897.7 .쓰298 2023",
            "CB113.H4 .H3713 2015", "QA76.73 .P98 .V38 2020 v.2 c.1",
            "QA76.73", "PR2993 .F2.P45", "QA76.73\n.P98\t.V38\n2020"
        ]
        for raw in examples {
            let number = BookNavigationArrivalCallNumber(raw)!
            let layout = makeLayout(number)
            precondition((1...3).contains(layout.lines.count))
            precondition(layout.lines.allSatisfy { !$0.contains("\n") && !$0.contains("\t") })
            precondition(layout.lines.joined().filter { !$0.isWhitespace } == number.rawValue.filter { !$0.isWhitespace },
                "연도·권차를 버리지 않고 세 줄 안에 보존한다")
            verifyFit(layout)
        }
        let reported = BookNavigationArrivalCallNumber(examples[0])!
        precondition(reported.stickerLines == ["QA76.73", ".P98", ".V38 2020"])

        let short = makeLayout(.init("QA1234")!)
        precondition(short.size.width == 96 && short.fontSize == 20)
        let shrinking = makeLayout(.init("QA12345")!)
        precondition(shrinking.size.width == 96 && shrinking.fontSize >= 19 && shrinking.fontSize < 20)
        let growing = makeLayout(.init("QA123456")!)
        precondition(growing.size.width > 96 && growing.fontSize == 19,
            "19pt까지 먼저 줄인 다음에만 폭을 늘린다")
        for layout in [short, shrinking, growing] { verifyFit(layout) }

        let veryLong = BookNavigationArrivalCallNumber("QA1234567890123456 .ABCDEFGHIJKLMNOPQRSTUVWXYZ .V123456789 2020 c.1")!
        let bounded = makeLayout(veryLong, maximumWidth: 180)
        precondition(bounded.size.width == 180 && bounded.fontSize < 19)
        verifyFit(bounded)
        precondition(bounded.lines.joined().filter { !$0.isWhitespace } == veryLong.rawValue.filter { !$0.isWhitespace })

        var smallCases = 0
        for raw in examples + [veryLong.rawValue] {
            let large = makeLayout(.init(raw)!)
            for width: CGFloat in [4, 8, 25, 47, 70, 110] {
                let target = CGSize(width: width, height: 59)
                let small = large.fitted(to: target, measureText: measure)
                precondition(small.size == target && small.lines == large.lines)
                precondition(small.fontSize <= 20 * small.scale)
                verifyFit(small)
                smallCases += 1
            }
        }
        let target = CGSize(width: 25, height: 59)
        precondition(short.fitted(to: target, measureText: measure).size == growing.fitted(to: target, measureText: measure).size,
            "청구기호 길이가 바뀌어도 이미지가 정한 작은 번호표 크기는 바뀌지 않는다")
        print("PASS: max three lines without data loss; 20→19pt before width growth, bounded long symbols and \(smallCases) image-sized sticker cases.")
    }

    private static func measure(_ text: String, _ fontSize: CGFloat, _ first: Bool) -> CGFloat {
        CGFloat(text.count) * fontSize * 0.5 * (first ? 1.05 : 1)
    }
    private static func makeLayout(_ number: BookNavigationArrivalCallNumber, maximumWidth: CGFloat? = nil) -> BookNavigationCallNumberLabelLayout {
        .init(callNumber: number, maximumWidth: maximumWidth, measureText: measure)
    }
    private static func verifyFit(_ layout: BookNavigationCallNumberLabelLayout) {
        precondition(layout.size.width > 0 && layout.size.width.isFinite && layout.fontSize > 0)
        for (index, line) in layout.lines.enumerated() {
            precondition(measure(line, layout.fontSize, index == 0) <= layout.size.width - layout.horizontalPadding * 2 + 0.01,
                "각 행이 한 줄 안에 들어가며 네 번째 줄로 넘치지 않는다")
        }
        precondition(CGFloat(layout.lines.count) * layout.lineHeight + layout.verticalPadding * 2 <= layout.upperHeight + 0.01)
    }
}
