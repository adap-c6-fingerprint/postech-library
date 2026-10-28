import Foundation
import Testing

@testable import fingerprint_library

nonisolated struct BookBasketIsolationTests {
    @Test("메인 액터 밖에서도 장바구니의 중복 판정·보관 한도·저장이 동작한다")
    func addsFromBackground() async {
        let results = await Task.detached {
            let suite = "BookBasketIsolationTests.\(UUID().uuidString)"
            defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
            let client = BookBasketClient.userDefaults(suiteName: suite)
            func book(_ id: String, control: String) -> Book {
                Book(id: id, isbn: nil, controlNumber: control, title: "동물농장", author: "Orwell",
                     publisher: nil, publicationYear: nil, description: nil, imageURL: nil)
            }
            let first = book("a", control: "primo:animal-farm")
            let added = client.add(first, at: .distantPast)
            let duplicate = client.add(book("b", control: "primo:animal-farm"), at: .distantPast)
            let retained = client.load() == [BookBasketItem(book: first, addedAt: .distantPast)]
            client.save((0..<BookBasketItem.maxStoredCount).map {
                BookBasketItem(book: book("\($0)", control: "primo:\($0)"), addedAt: .distantPast)
            })
            let full = client.load()
            let rejected = client.add(first, at: .distantPast)
            return (added, duplicate, retained, rejected, client.load() == full)
        }.value
        #expect(results.0 == .added)
        #expect(results.1 == .alreadyAdded)
        #expect(results.2)
        #expect(results.3 == .limitExceeded)
        #expect(results.4)
    }
}
