import CoreGraphics
import Testing
@testable import fingerprint_library

struct BookCoverFitTests {
    @Test(arguments: [
        (CGFloat(0.65), CGSize(width: 140, height: 140 / 0.65)),
        (CGFloat(0.9), CGSize(width: 140, height: 140 / 0.9)),
        (CGFloat(1.2), CGSize(width: 140, height: 140 / 1.2))
    ])
    func 가로만_정해지면_세로는_표지_비율로_정한다(ratio: CGFloat, expected: CGSize) {
        #expect(BookCoverFit.containerSize(width: 140, height: nil, aspectRatio: ratio) == expected)
    }

    @Test func 비율을_모르면_칸_크기를_정하지_않는다() {
        #expect(BookCoverFit.containerSize(width: 140, height: nil, aspectRatio: nil) == nil)
        #expect(BookCoverFit.containerSize(width: 140, height: .infinity, aspectRatio: nil) == nil)
    }

    @Test func 가로세로가_정해지면_칸_크기를_그대로_쓴다() {
        #expect(BookCoverFit.containerSize(width: 78, height: 111, aspectRatio: 0.9) == CGSize(width: 78, height: 111))
    }

    @Test func 세로로_긴_표지는_칸_높이에_맞춘다() {
        let size = BookCoverFit.fittedSize(aspectRatio: 0.5, in: CGSize(width: 78, height: 111))
        #expect(size == CGSize(width: 55.5, height: 111))
    }

    @Test func 넓적한_표지는_칸_너비에_맞춘다() {
        let size = BookCoverFit.fittedSize(aspectRatio: 1, in: CGSize(width: 78, height: 111))
        #expect(size == CGSize(width: 78, height: 78))
    }

    @Test func 비율을_모르면_칸_전체를_쓴다() {
        #expect(BookCoverFit.fittedSize(aspectRatio: nil, in: CGSize(width: 140, height: 186)) == CGSize(width: 140, height: 186))
        #expect(BookCoverFit.aspectRatio(of: .zero) == nil)
    }

    @Test func 상세_시트_높이는_표지_높이를_따른다() {
        let base = BookDetailCompactLayout.topPadding + BookDetailCompactLayout.actionsHeight
        #expect(BookDetailCompactLayout.height(coverHeight: 215) == base + 215)
        #expect(BookDetailCompactLayout.height(coverHeight: 0) == base + BookDetailCompactLayout.coverSize.height)
    }
}
