import Testing
@testable import fingerprint_library

struct ShelfResolverTests {
    @Test(arguments: [
        ("삼각서가C3: 원북 원포항 선정도서 (2층)", "삼각서가 C"),
        ("삼각 서가 a1", "삼각서가 A"),
    ])
    func 삼각서가_위치_이름에서_도면_서가_이름을_만든다(locationName: String, expected: String) {
        #expect(ShelfResolver.displayShelfName(in: locationName) == expected)
    }

    @Test func 삼각서가가_아닌_위치는_서가로_추측하지_않는다() {
        #expect(ShelfResolver.displayShelfName(in: "3층 일반자료실") == nil)
        #expect(ShelfResolver.displayShelfName(in: nil) == nil)
    }
}
