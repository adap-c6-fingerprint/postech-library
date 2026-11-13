//
//  RecommendationDataset.swift
//  fingerprint-library
//
//  ✅ 이슈 #237: 앱에 넣은 추천 하드데이터(RecommendationDataset.json)를 앱 모델로 옮긴 것.
//  JSON 형식(DTO)은 Clients에 두고, 여기에는 화면·추천 로직이 쓰는 값만 둔다.
//

import Foundation

nonisolated struct RecommendationDataset: Equatable, Sendable {
    nonisolated struct AffiliationPath: Hashable, Sendable {
        let parent: String
        let group: String
        let name: String

        var key: [String] { [parent, group, name] }

        init(parent: String, group: String, name: String) {
            self.parent = parent
            self.group = group
            self.name = name
        }

        init?(key: [String]) {
            guard key.count == 3 else { return nil }
            self.init(parent: key[0], group: key[1], name: key[2])
        }
    }

    let affiliationPaths: [AffiliationPath]
    let preferenceNames: [String]

    private let booksByRecordID: [String: Book]
    private let affiliationRecordIDs: [AffiliationPath: [String]]
    private let preferenceRecordIDs: [String: [String]]

    init(
        books: [String: Book],
        affiliations: [(path: AffiliationPath, recordIDs: [String])],
        preferences: [(name: String, recordIDs: [String])]
    ) {
        booksByRecordID = books
        affiliationPaths = affiliations.map(\.path)
        preferenceNames = preferences.map(\.name)
        affiliationRecordIDs = Dictionary(affiliations.map { ($0.path, $0.recordIDs) }) { first, _ in first }
        preferenceRecordIDs = Dictionary(preferences.map { ($0.name, $0.recordIDs) }) { first, _ in first }
    }

    static let empty = RecommendationDataset(books: [:], affiliations: [], preferences: [])

    var bookCount: Int { booksByRecordID.count }

    func book(recordID: String) -> Book? {
        booksByRecordID[recordID]
    }

    var allBooks: [Book] {
        booksByRecordID.keys.sorted().compactMap { booksByRecordID[$0] }
    }

    func books(forAffiliation path: AffiliationPath) -> [Book] {
        (affiliationRecordIDs[path] ?? []).compactMap { booksByRecordID[$0] }
    }

    func books(forPreferences names: [String]) -> [Book] {
        var seen = Set<String>()
        return names
            .flatMap { preferenceRecordIDs[$0] ?? [] }
            .filter { seen.insert($0).inserted }
            .compactMap { booksByRecordID[$0] }
    }

    func books(inSamePreferencesAs anchors: [Book]) -> [Book] {
        for anchor in anchors {
            let keys = DatasetRecommendation.identityKeys(of: anchor)
            let matchingPreferences = preferenceNames.filter { name in
                books(forPreferences: [name]).contains { book in
                    !keys.isDisjoint(with: DatasetRecommendation.identityKeys(of: book))
                }
            }
            if !matchingPreferences.isEmpty { return books(forPreferences: matchingPreferences) }
        }
        return []
    }

    func recordIDs(forAffiliation path: AffiliationPath) -> [String] {
        affiliationRecordIDs[path] ?? []
    }

    func recordIDs(forPreference name: String) -> [String] {
        preferenceRecordIDs[name] ?? []
    }

    var parents: [String] {
        var seen = Set<String>()
        return affiliationPaths.map(\.parent).filter { seen.insert($0).inserted }
    }

    func groups(in parent: String) -> [String] {
        var seen = Set<String>()
        return affiliationPaths.filter { $0.parent == parent }.map(\.group).filter { seen.insert($0).inserted }
    }

    func paths(in parent: String, group: String) -> [AffiliationPath] {
        affiliationPaths.filter { $0.parent == parent && $0.group == group }
    }
}
