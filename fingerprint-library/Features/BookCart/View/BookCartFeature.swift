//
//  BookCartFeature.swift
//  fingerprint-library
//

import Foundation
import ComposableArchitecture

@Reducer
struct BookCartFeature {
    @ObservableState
    struct State: Equatable {
        var items: [BookCartItem] = []
        var libraryInfo: [Book.ID: LibraryInfo] = [:]
        // 길안내하거나 삭제할 책을 고른 순서대로 보관한다.
        var selectedIDs: [Book.ID] = []
        var isRemoveAlertPresented = false

        var sections: [BookCartSection] {
            BookCartSection.grouped(items, calendar: .current)
        }

        var selectedCount: Int { selectedBooks.count }

        var canStartGuidance: Bool {
            (1...BookCartItem.maxGuidanceCount).contains(selectedCount)
        }

        // 아직 장바구니에 남아 있는 선택 책만 고른 순서대로 돌려준다.
        var selectedBooks: [Book] {
            selectedIDs.compactMap { id in items.first { $0.id == id }?.book }
        }
    }

    struct LibraryInfo: Equatable {
        let location: String?
        let availability: BookCardLibraryInfo.Availability?
    }

    enum Action {
        case task
        case loadLibraryInfo
        case libraryInfoLoaded(Book.ID, [BookHolding])
        case coverRecovered(Book.ID, URL, URL)
        case selectionToggled(Book.ID)
        case startGuidanceButtonTapped
        // "안내 시작하기"를 눌러 경로 미리보기로 넘어갈 때. 마이페이지 최근 찾은 책에 기록한다.
        case guidanceLinkTapped
        case removeButtonTapped
        case removeConfirmed
        case removeAlertDismissed
        case delegate(Delegate)

        @CasePathable
        enum Delegate: Equatable {
            // 목적 서가 확인 및 경로 미리보기 화면으로 넘길 책
            case startGuidance([Book])
        }
    }

    @Dependency(\.bookCartClient)
    var bookCartClient: BookCartClient
    @Dependency(\.analyticsClient) private var analytics

    @Dependency(\.bookHoldingsClient) var bookHoldingsClient
    @Dependency(\.bookLocationCacheClient) var bookLocationCacheClient
    @Dependency(\.recentlyFoundBooksClient) var recentlyFoundBooksClient
    @Dependency(\.bookCoverClient) var bookCoverClient

    private nonisolated enum CancelID: Hashable, Sendable {
        case libraryInfo
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .task:
                state.items = bookCartClient.load()
                let itemIDs = Set(state.items.map(\.id))
                state.selectedIDs.removeAll { !itemIDs.contains($0) }
                return .none

            case .loadLibraryInfo:
                return loadLibraryInfo(state: &state)

            case let .libraryInfoLoaded(id, holdings):
                guard let book = state.items.first(where: { $0.id == id })?.book else { return .none }
                let info = BookCardLibraryInfo(holdings: holdings)
                state.libraryInfo[id] = LibraryInfo(location: info.location, availability: info.availability)
                bookLocationCacheClient.record(book, holdings)
                return .none

            case let .coverRecovered(id, oldURL, newURL):
                bookCartClient.repairLegacyCover(id, oldURL, newURL)
                state.items = bookCartClient.load()
                return .none

            case let .selectionToggled(id):
                guard state.items.contains(where: { $0.id == id }) else { return .none }
                if let index = state.selectedIDs.firstIndex(of: id) {
                    state.selectedIDs.remove(at: index)
                } else {
                    state.selectedIDs.append(id)
                }
                return .none

            case .startGuidanceButtonTapped:
                guard state.canStartGuidance else { return .none }
                return .send(.delegate(.startGuidance(state.selectedBooks)))

            case .guidanceLinkTapped:
                guard state.canStartGuidance else { return .none }
                recentlyFoundBooksClient.record(state.selectedBooks)
                // 고른 순서대로 책장 왼쪽부터 꽂힌다.
                bookCoverClient.prefetchSpines(state.selectedBooks.compactMap(\.isbn))
                // 책장에 꽂히는 순간 책등을 미리 받아 둔다. 책찾기 화면과 마이페이지 책장이 로딩 없이 바로 그린다.
                return .none

            case .removeButtonTapped:
                guard !state.selectedBooks.isEmpty else { return .none }
                state.isRemoveAlertPresented = true
                return .none

            case .removeConfirmed:
                state.isRemoveAlertPresented = false
                let removedIDs = Set(state.selectedIDs)
                let storedItems = bookCartClient.load()
                state.items = storedItems.filter { !removedIDs.contains($0.id) }
                let removedCount = storedItems.count - state.items.count
                state.selectedIDs = []
                bookCartClient.save(state.items)
                if removedCount > 0 {
                    analytics.record(.init(.cartBooksRemoved, [.removedCount: .integer(removedCount)]))
                }
                return .none

            case .removeAlertDismissed:
                state.isRemoveAlertPresented = false
                return .none

            case .delegate:
                return .none
            }
        }
    }

    private func loadLibraryInfo(state: inout State) -> Effect<Action> {
        let books = state.items.map(\.book)
        let keys = Set(books.map(\.recordKey))
        let cached = bookLocationCacheClient.load(keys)
        let recent = bookLocationCacheClient.loadRecent(keys)
        state.libraryInfo = [:]
        var requests: [(id: Book.ID, recordID: String)] = []

        for book in books {
            if let holdings = recent[book.recordKey] {
                let info = BookCardLibraryInfo(holdings: holdings)
                state.libraryInfo[book.id] = LibraryInfo(location: info.location, availability: info.availability)
            } else {
                if let holdings = cached[book.recordKey] {
                    let location = BookCardLibraryInfo(holdings: holdings).location
                    state.libraryInfo[book.id] = LibraryInfo(location: location, availability: nil)
                }
                if let recordID = BookHoldingsClient.recordID(for: book) {
                    requests.append((book.id, recordID))
                }
            }
        }

        return .run { [bookHoldingsClient, requests] send in
            for start in stride(from: 0, to: requests.count, by: 3) {
                guard !Task.isCancelled else { return }
                await withTaskGroup(of: Void.self) { group in
                    for request in requests[start..<min(start + 3, requests.count)] {
                        group.addTask {
                            guard let holdings = try? await bookHoldingsClient.fetch(request.recordID),
                                  !Task.isCancelled else { return }
                            await send(.libraryInfoLoaded(request.id, holdings))
                        }
                    }
                }
            }
        }
        .cancellable(id: CancelID.libraryInfo, cancelInFlight: true)
    }
}
