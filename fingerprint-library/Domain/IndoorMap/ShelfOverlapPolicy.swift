import Foundation

/// #73에서 확인한 인접 서가 쌍과 같은 책장의 A/B면만 한 탐색 구역으로 안내한다.
/// 같은 층이라는 이유만으로 떨어진 소장처를 하나로 묶지 않는다.
nonisolated struct ShelfOverlapPolicy {
    func allows(_ shelves: [IndoorShelfLabel]) -> Bool {
        guard (1...2).contains(shelves.count),
              Set(shelves.map(\.id)).count == shelves.count,
              Set(shelves.map(\.floorID)).count == 1 else { return false }
        guard shelves.count == 2 else { return true }
        let pair = Set(shelves.map(\.fixtureNumber))
        if Self.confirmedPairs.contains(pair) { return true }
        return shelves[0].fixtureNumber.dropLast() == shelves[1].fixtureNumber.dropLast()
            && shelves[0].side != shelves[1].side
    }

    private static let confirmedPairs: [Set<String>] = [
        ["S-3F-653-B", "S-3F-651-A"], // 303-B / 304-A
        ["S-3F-524-A", "S-3F-524-B"], // 319-A / 319-B
        ["S-3F-528-B", "S-3F-530-A"], // 321-B / 322-A
        ["S-3F-558-B", "S-3F-560-A"], // 334-B / 335-A
        ["S-3F-644-A", "S-3F-642-B"]  // 351-A / 352-B
    ]
}
