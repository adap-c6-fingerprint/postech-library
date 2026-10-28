import Foundation

/// 선택한 책의 식별자와 명시적으로 연결된 지도 서가 키.
/// API의 소장 구역·청구기호를 이 키로 해석하는 규칙은 별도 합의가 필요하다.
nonisolated struct BookShelfSelection: Equatable, Sendable {
    let bookID: String
    let shelfKey: ShelfKey?
}

/// 입력 책 한 권의 결과. 실패한 책도 입력 순서와 식별자를 보존한다.
nonisolated struct BookShelfResolution: Equatable, Sendable {
    enum Outcome: Equatable, Sendable {
        case resolved(ShelfDestination)
        case unresolved(Failure)
    }

    enum Failure: Equatable, Sendable {
        case invalidBookID
        case missingLocation
        case differentDataset(ShelfKey)
        case unmappedShelf(ShelfKey)
    }

    let bookID: String
    let outcome: Outcome
}

/// 같은 서가에 연결된 책 목록. 배열 순서는 입력에서 처음 등장한 순서이며 최적 방문 순서가 아니다.
nonisolated struct ShelfBookGroup: Equatable, Sendable {
    let destination: ShelfDestination
    var bookIDs: [String]
}

nonisolated struct BookShelfMapping: Equatable, Sendable {
    let entries: [BookShelfResolution]

    var unresolved: [BookShelfResolution] {
        entries.filter { if case .unresolved = $0.outcome { true } else { false } }
    }

    enum GroupingError: Error, Equatable, Sendable {
        case emptySelection
        case unresolvedBooks([String])
    }

    /// 모든 책이 연결된 경우에만 방문 대상 묶음을 반환한다.
    /// 실패한 책을 제외한 부분 경로가 정상 결과로 사용되지 않게 한다.
    func groupedDestinations() throws -> [ShelfBookGroup] {
        guard !entries.isEmpty else { throw GroupingError.emptySelection }
        let failures = unresolved
        guard failures.isEmpty else { throw GroupingError.unresolvedBooks(failures.map(\.bookID)) }
        var groups: [ShelfBookGroup] = []
        var indices: [ShelfKey: Int] = [:]
        for entry in entries {
            guard case .resolved(let destination) = entry.outcome else { continue }
            if let index = indices[destination.key] {
                groups[index].bookIDs.append(entry.bookID)
            } else {
                indices[destination.key] = groups.count
                groups.append(.init(destination: destination, bookIDs: [entry.bookID]))
            }
        }
        return groups
    }
}

/// 선택한 책을 검증된 지도 서가·도착 노드로 연결하는 순수 규칙.
/// 책 제목·API 표시 문자열·좌표 근접도로 서가를 추측하지 않는다.
nonisolated struct BookShelfResolver {
    /// 입력마다 결과 하나를 반환한다. 실제 API 연결 전에는 명시적인 테스트용 키로 검증한다.
    func resolve(_ selections: [BookShelfSelection], in directory: ShelfDirectory) -> BookShelfMapping {
        BookShelfMapping(entries: selections.map { selection in
            let outcome: BookShelfResolution.Outcome
            if selection.bookID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                outcome = .unresolved(.invalidBookID)
            } else if let key = selection.shelfKey {
                if key.datasetID != directory.datasetID {
                    outcome = .unresolved(.differentDataset(key))
                } else if let destination = try? directory.destination(for: key) {
                    outcome = .resolved(destination)
                } else {
                    outcome = .unresolved(.unmappedShelf(key))
                }
            } else {
                outcome = .unresolved(.missingLocation)
            }
            return .init(bookID: selection.bookID, outcome: outcome)
        })
    }
}
