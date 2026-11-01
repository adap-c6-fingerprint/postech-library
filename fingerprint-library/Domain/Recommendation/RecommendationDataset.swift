//
//  RecommendationDataset.swift
//  fingerprint-library
//
//  ✅ 이슈 #237: 앱에 넣은 추천 하드데이터(RecommendationDataset.json)를 앱 모델로 옮긴 것.
//  JSON 형식(DTO)은 Clients에 두고, 여기에는 화면·추천 로직이 쓰는 값만 둔다.
//

import Foundation

nonisolated struct RecommendationDataset: Equatable, Sendable {
    /// 소속 하나의 3단계 경로. 이름만으로는 학부·대학원의 같은 학과가 섞이므로 세 값을 함께 쓴다.
    nonisolated struct AffiliationPath: Hashable, Sendable {
        let parent: String // 상위 소속. 예: "POSTECH 학부"
        let group: String  // 중위 그룹. 예: "학과 및 학부"
        let name: String   // 최종 소속. 예: "수학과"

        /// 저장·조회에 쓰는 키. JSON의 selectionKey와 같은 순서다.
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

    /// 화면에 보여줄 순서 그대로의 소속 경로 301개.
    let affiliationPaths: [AffiliationPath]
    /// 화면에 보여줄 순서 그대로의 선호 분류 20개.
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
        // 같은 키가 두 번 나오면 뒤의 값을 버린다. 원본은 중복이 없음을 테스트로 확인한다.
        affiliationRecordIDs = Dictionary(affiliations.map { ($0.path, $0.recordIDs) }) { first, _ in first }
        preferenceRecordIDs = Dictionary(preferences.map { ($0.name, $0.recordIDs) }) { first, _ in first }
    }

    static let empty = RecommendationDataset(books: [:], affiliations: [], preferences: [])

    var bookCount: Int { booksByRecordID.count }

    func book(recordID: String) -> Book? {
        booksByRecordID[recordID]
    }

    /// 소속 목록의 도서. 표시 순서일 뿐 인기순이 아니다.
    func books(forAffiliation path: AffiliationPath) -> [Book] {
        (affiliationRecordIDs[path] ?? []).compactMap { booksByRecordID[$0] }
    }

    /// 여러 선호 분류의 목록을 합치고 recordID로 중복을 뺀다. (Q3)
    func books(forPreferences names: [String]) -> [Book] {
        var seen = Set<String>()
        return names
            .flatMap { preferenceRecordIDs[$0] ?? [] }
            .filter { seen.insert($0).inserted }
            .compactMap { booksByRecordID[$0] }
    }

    func recordIDs(forAffiliation path: AffiliationPath) -> [String] {
        affiliationRecordIDs[path] ?? []
    }

    func recordIDs(forPreference name: String) -> [String] {
        preferenceRecordIDs[name] ?? []
    }

    // MARK: - 온보딩 3단계 선택지

    /// 상위 소속을 원본 순서대로 한 번씩.
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
