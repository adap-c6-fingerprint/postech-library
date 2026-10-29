import Foundation
import SwiftData
import Testing
@testable import fingerprint_library

@MainActor
struct BookStorageCompatibilityTests {
    @Test("기존 배포 키·JSON 형식의 장바구니·찜·검색 기록을 그대로 복원한다")
    func readsExistingStorage() throws {
        let suite = "BookStorageCompatibilityTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let record: [String: Any] = ["id": "book", "controlNumber": "primo:alma1",
            "title": "기존 도서", "author": "저자", "addedAt": 100.0]
        defaults.set(try JSONSerialization.data(withJSONObject: [record]), forKey: "bookBasketItems")
        let keys: Set<[String?]> = [["control", "primo:alma1"]]
        defaults.set(try JSONEncoder().encode(keys), forKey: "favoriteBookRecordKeys")
        defaults.set(["기존 검색어"], forKey: "recentSearchQueries")

        let items = BookBasketClient.userDefaults(suiteName: suite).load()
        #expect(items.count == 1 && items.first?.book.title == "기존 도서")
        #expect(items.first?.addedAt == Date(timeIntervalSinceReferenceDate: 100))
        #expect(BookFavoritesClient.userDefaults(suiteName: suite).load() == keys)
        #expect(SearchHistoryClient.userDefaults(suiteName: suite).load() == ["기존 검색어"])
        #expect(BookStorageKey.basketItems == "bookBasketItems")
        #expect(BookStorageKey.favoriteRecordKeys == "favoriteBookRecordKeys")
        #expect(BookStorageKey.recentSearchQueries == "recentSearchQueries")
    }

    @Test("찜 토글은 다른 화면이 추가한 책을 보존하고 같은 자료번호만 해제한다")
    func toggleUsesLatestStorage() {
        let suite = "BookStorageCompatibilityTests.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let client = BookFavoritesClient.userDefaults(suiteName: suite)
        let selected = Book(id: "book", isbn: nil, controlNumber: "primo:alma1", title: "도서", author: "저자",
            publisher: nil, publicationYear: nil, description: nil, imageURL: nil)
        let other: [String?] = ["control", "primo:alma2"]
        client.save([other])
        #expect(client.toggle(selected) == [other, selected.recordKey])
        #expect(client.toggle(selected) == [other])
        #expect(client.load() == [other])
    }

    @Test("프로필 값 분리 후에도 검증·갱신·단일 레코드 저장과 스냅샷을 유지한다")
    func profileStorageIsUnchanged() throws {
        let container = try ModelContainer(for: UserProfile.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        #expect(try !UserProfile.exists(in: context))
        try UserProfile.save(departmentName: " 수학과 ", interests: ["Q", "Q", "T"], in: context)
        let profile = try UserProfile.fetchOrCreate(in: context)
        #expect(profile.snapshot == UserProfileSnapshot(departmentName: "수학과", interests: ["Q", "T"]))
        #expect(profile.snapshot.promptText == "학과: 수학과\n관심사: Q, T")
        try UserProfile.save(departmentName: "물리학과", interests: ["Q"], in: context)
        #expect(try context.fetchCount(FetchDescriptor<UserProfile>()) == 1)
        #expect(profile.departmentName == "물리학과")
        #expect(throws: UserProfileError.emptyDepartmentName) {
            try profile.updateDepartmentName(" ")
        }
        #expect(profile.departmentName == "물리학과")
    }
}
