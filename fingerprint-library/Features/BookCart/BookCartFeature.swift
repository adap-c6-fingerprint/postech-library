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
        var libraryInfo: [Book.ID: LibraryInfo] = [:]
        var selectedIDs: [Book.ID] = []
        @Shared(.hasShownCartGuidanceLimitAlert) var hasShownGuidanceLimitAlert
        var isGuidanceLimitAlertPresented = false
        var isRemoveAlertPresented = false

        var sections: [BookCartSection] {
            BookCartSection.grouped(items, calendar: .current)
        }

        var selectedCount: Int { selectedBooks.count }

        var canStartGuidance: Bool {
            (1...BookCartItem.maxGuidanceCount).contains(selectedCount)
        }

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
        case guidanceLimitAlertDismissed
        case guidanceLinkTapped
        case removeButtonTapped
        case removeConfirmed
        case removeAlertDismissed
        case delegate(Delegate)

        @CasePathable
        enum Delegate: Equatable {
            case startGuidance([Book])
        }
    }

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
                state.libraryInfo[id] = LibraryInfo(location: info.location, availability: info.availability)
                bookLocationCacheClient.record(book, holdings)
                return .none

            case let .coverRecovered(id, oldURL, newURL):
                state.$items.withLock { $0.repairLegacyCover(of: id, from: oldURL, to: newURL) }
                return .none

            case let .selectionToggled(id):
                guard state.items.contains(where: { $0.id == id }) else { return .none }
                if let index = state.selectedIDs.firstIndex(of: id) {
                    state.selectedIDs.remove(at: index)
                } else {
                    state.selectedIDs.append(id)
                    if state.selectedCount == BookCartItem.maxGuidanceCount + 1,
                       !state.hasShownGuidanceLimitAlert {
                        state.$hasShownGuidanceLimitAlert.withLock { $0 = true }
                        state.isGuidanceLimitAlertPresented = true
                    }
                }
                return .none

            case .guidanceLimitAlertDismissed:
                state.isGuidanceLimitAlertPresented = false
                return .none

            case .guidanceLinkTapped:
                guard state.canStartGuidance else { return .none }
                recentlyFoundBooksClient.record(state.selectedBooks)
                bookCoverClient.prefetchSpines(state.selectedBooks.compactMap(\.isbn))
                return .send(.delegate(.startGuidance(state.selectedBooks)))

            case .removeButtonTapped:
                guard !state.selectedBooks.isEmpty else { return .none }
                state.isRemoveAlertPresented = true
                return .none

            case .removeConfirmed:
                state.isRemoveAlertPresented = false
                let removedKeys = Set(state.selectedBooks.map(\.recordKey))
                let removedCount = state.$items.withLock { $0.remove(recordKeys: removedKeys) }
                state.selectedIDs = []
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
