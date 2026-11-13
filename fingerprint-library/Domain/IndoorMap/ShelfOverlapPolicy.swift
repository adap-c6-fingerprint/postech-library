import Foundation

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
        ["S-3F-653-B", "S-3F-651-A"],
        ["S-3F-524-A", "S-3F-524-B"],
        ["S-3F-528-B", "S-3F-530-A"],
        ["S-3F-558-B", "S-3F-560-A"],
        ["S-3F-644-A", "S-3F-642-B"]
    ]
}
