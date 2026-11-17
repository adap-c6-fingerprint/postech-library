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
        @Shared(.bookCart) var items
        var libraryInfo: [Book.ID: BookLocationStatus] = [:]
        var selectedIDs: [Book.ID] = []
        @Shared(.hasShownCartGuidanceLimitAlert) var hasShownGuidanceLimitAlert
        var isGuidanceLimitAlertPresented = false
        var isRemoveAlertPresented = false
        var unavailableBookTitle: String?

        var sections: [BookCartSection] {
            BookCartSection.grouped(items, calendar: .current)
        }

        var selectedCount: Int { selectedBooks.count }

        var canStartGuidance: Bool {
            (1...BookCartItem.maxStoredCount).contains(selectedCount)
                && !selectedIDs.contains { libraryInfo[$0]?.availability == .unavailable }
        }

        var selectedBooks: [Book] {
            selectedIDs.compactMap { id in items.first { $0.id == id }?.book }
        }
    }

    enum Action {
        case task
        case loadLibraryInfo
        case libraryInfoLoaded(Book.ID, [BookHolding])
        case coverRecovered(Book.ID, URL, URL)
        case selectionToggled(Book.ID)
        case guidanceLimitAlertDismissed
        case unavailableBookAlertDismissed
        case guidanceLinkTapped
        case removeButtonTapped
        case removeConfirmed
        case removeAlertDismissed
        case removeCancelled
        // 삭제 알림의 "취소" 버튼
        case delegate(Delegate)

        @CasePathable
        enum Delegate: Equatable {
            case startGuidance([Book])
        }
    }

    @Dependency(\.analyticsClient) private var analytics

    @Dependency(\.bookHoldingsClient) var bookHoldingsClient
    @Dependency(\.bookLocationCacheClient) var bookLocationCacheClient
    @Dependency(\.bookCoverClient) var bookCoverClient
    @Dependency(\.uuid) var uuid

    private nonisolated enum CancelID: Hashable, Sendable {
        case libraryInfo
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            let itemIDs = Set(state.items.map(\.id))
            state.selectedIDs.removeAll { !itemIDs.contains($0) }

            switch action {
            case .task:
                return .none

            case .loadLibraryInfo:
                return loadLibraryInfo(state: &state)

            case let .libraryInfoLoaded(id, holdings):
                guard let book = state.items.first(where: { $0.id == id })?.book else { return .none }
                let info = BookCardLibraryInfo(holdings: holdings)
                state.libraryInfo[id] = BookLocationStatus(location: info.location, availability: info.availability)
                bookLocationCacheClient.record(book, holdings)
                removeUnavailableSelections(state: &state)
                return .none

            case let .coverRecovered(id, oldURL, newURL):
                state.$items.withLock { $0.repairLegacyCover(of: id, from: oldURL, to: newURL) }
                return .none

            case let .selectionToggled(id):
                guard let book = state.items.first(where: { $0.id == id })?.book else { return .none }
                if let index = state.selectedIDs.firstIndex(of: id) {
                    state.selectedIDs.remove(at: index)
                    analytics.record(.button(.bookDeselect, on: .cart, book: book))
                } else {
                    guard state.libraryInfo[id]?.availability != .unavailable else {
                        state.unavailableBookTitle = BookText.plainText(book.title)
                        return .none
                    }
                    state.selectedIDs.append(id)
                    analytics.record(.button(.bookSelect, on: .cart, book: book))
                    if state.selectedCount == BookCartItem.maxStoredCount + 1,
                       !state.hasShownGuidanceLimitAlert {
                        state.$hasShownGuidanceLimitAlert.withLock { $0 = true }
                        state.isGuidanceLimitAlertPresented = true
                    }
                }
                return .none

            case .guidanceLimitAlertDismissed:
                state.isGuidanceLimitAlertPresented = false
                return .none

            case .unavailableBookAlertDismissed:
                state.unavailableBookTitle = nil
                return .none

            case .guidanceLinkTapped:
                guard !removeUnavailableSelections(state: &state) else { return .none }
                analytics.record(.button(.startGuidance, on: .cart, [.bookCount: .integer(state.selectedCount)]))
                // 책별 기록은 경로 미리보기의 route_book_included가 맡는다
                guard state.canStartGuidance else { return .none }
                bookCoverClient.prefetchSpines(state.selectedBooks.compactMap(\.isbn))
                return .send(.delegate(.startGuidance(state.selectedBooks)))

            case .removeButtonTapped:
                analytics.record(.button(.delete, on: .cart, [.bookCount: .integer(state.selectedCount)]))
                // 휴지통. 여러 권이라 책 ID 대신 권수를 보낸다
                guard !state.selectedBooks.isEmpty else { return .none }
                state.isRemoveAlertPresented = true
                return .none

            case .removeConfirmed:
                state.isRemoveAlertPresented = false
                let removedBooks = state.selectedBooks
                analytics.record(.button(.deleteConfirm, on: .cart, [.bookCount: .integer(removedBooks.count)]))
                let removedKeys = Set(removedBooks.map(\.recordKey))
                let removedCount = state.$items.withLock { $0.remove(recordKeys: removedKeys) }
                state.selectedIDs = []
                if removedCount > 0 {
                    let operation = uuid().uuidString
                    // 이번 삭제 한 번에서 나온 줄들을 묶는 ID
                    analytics.record(.init(.cartBooksRemoved, [
                        .operationID: .text(operation), .removedCount: .integer(removedCount)
                    ]))
                    for book in removedBooks {
                        analytics.record(.init(.cartBookRemoved, AnalyticsEvent.bookFields(book)
                            .merging([.operationID: .text(operation)]) { $1 }))
                    }
                    // 삭제한 책마다 한 줄
                }
                return .none

            case .removeAlertDismissed:
                state.isRemoveAlertPresented = false
                return .none

            case .removeCancelled:
                analytics.record(.button(.deleteCancel, on: .cart, [.bookCount: .integer(state.selectedCount)]))
                state.isRemoveAlertPresented = false
                return .none

            case .delegate:
                return .none
            }
        }
    }

    @discardableResult
    private func removeUnavailableSelections(state: inout State) -> Bool {
        let unavailableIDs = Set(state.selectedIDs.filter { state.libraryInfo[$0]?.availability == .unavailable })
        guard let book = state.selectedBooks.first(where: { unavailableIDs.contains($0.id) }) else { return false }
        state.selectedIDs.removeAll { unavailableIDs.contains($0) }
        state.unavailableBookTitle = BookText.plainText(book.title)
        return true
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
                state.libraryInfo[book.id] = BookLocationStatus(location: info.location, availability: info.availability)
            } else {
                if let holdings = cached[book.recordKey] {
                    let location = BookCardLibraryInfo(holdings: holdings).location
                    state.libraryInfo[book.id] = BookLocationStatus(location: location, availability: nil)
                }
                if let recordID = BookHoldingsClient.recordID(for: book) {
                    requests.append((book.id, recordID))
                }
            }
        }

        removeUnavailableSelections(state: &state)

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
