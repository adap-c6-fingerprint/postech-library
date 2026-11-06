import Foundation

@main
struct VerifyMultiBookPreview {
    static func main() {
        // 같은 제목이라도 서로 다른 소장 도서를 ID로 구분해야 한다.
        let first = book("first", title: "같은 제목")
        let second = book("second", title: "같은 제목")
        let third = book("third", title: "세 번째 책")
        let original = [first, second, third]
        var selection = BookRoutePreviewSelection()

        precondition(selection.bookID(in: []) == nil)
        precondition(selection.bookID(in: [first]) == first.id)
        precondition(selection.bookID(in: [first, second]) == first.id)

        // 사용자가 아직 선택하지 않았다면 계산된 경로의 첫 책부터 보여 준다.
        precondition(selection.bookID(in: [third, second, first]) == third.id)

        // 상단 버튼과 페이지 스와이프는 같은 select 경로를 사용한다.
        selection.select(second.id, in: original)
        precondition(selection.bookID(in: original) == second.id)
        precondition(original.map(\.id) == [first.id, second.id, third.id])

        // 비동기 경로 계산으로 방문 순서가 바뀌어도 선택한 책은 유지한다.
        let optimized = [third, first, second]
        selection.reconcile(with: optimized)
        precondition(selection.bookID(in: optimized) == second.id)

        selection.select(third.id, in: optimized)
        precondition(selection.bookID(in: optimized) == third.id)
        selection.select(first.id, in: optimized)
        precondition(selection.bookID(in: optimized) == first.id)

        // 페이지 전환 중의 nil이나 오래된 ID가 현재 선택을 덮어쓰면 안 된다.
        selection.select(nil, in: optimized)
        selection.select("removed", in: optimized)
        precondition(selection.bookID(in: optimized) == first.id)

        // 선택 도서가 제거되는 프레임에서도 없는 페이지 ID를 반환하지 않는다.
        let remaining = [third, second]
        precondition(selection.bookID(in: remaining) == third.id)
        selection.reconcile(with: remaining)
        precondition(selection.selectedBookID == nil)
        precondition(selection.bookID(in: remaining) == third.id)

        selection.reconcile(with: [])
        precondition(selection.bookID(in: []) == nil)
        print("PASS: two/three books, duplicate titles, shared selection, route reorder, invalid IDs, removed books")
    }

    private static func book(_ id: String, title: String) -> Book {
        Book(id: id, isbn: nil, controlNumber: nil, title: title, author: "",
             publisher: nil, publicationYear: nil, description: nil, imageURL: nil)
    }
}
