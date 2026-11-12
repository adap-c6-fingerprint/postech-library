//
//  BookFavoritesFeature.swift
//  fingerprint-library
//

import Foundation
import ComposableArchitecture

@Reducer
struct BookFavoritesFeature {
    @ObservableState
    struct State: Equatable {
        @Shared(.favoriteBookKeys) var favoriteBookKeys
        @Shared(.favoriteBookRecords) var favoriteBookRecords
        var items: [BookFavoriteItem] { favoriteBookRecords.active(in: favoriteBookKeys) }
        var libraryInfo: [Book.ID: BookCartFeature.LibraryInfo] = [:]
        var selectedIDs: [Book.ID] = []
        var isAddedToCartAlertPresented = false
        var isCartLimitAlertPresented = false

        var sections: [BookFavoriteSection] {
            BookFavoriteSection.grouped(items, calendar: .current)
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
        case removeButtonTapped
        case addToCartButtonTapped
        case addedToCartAlertDismissed
        case goToCartButtonTapped
        case cartLimitAlertDismissed
        case delegate(Delegate)

        @CasePathable
        enum Delegate: Equatable {
            case showCart
        }
    }

    @Dependency(\.bookHoldingsClient) var bookHoldingsClient
    @Dependency(\.bookLocationCacheClient) var bookLocationCacheClient
    @Dependency(\.date.now) var now
    @Dependency(\.analyticsClient) private var analytics

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
                state.libraryInfo[id] = .init(location: info.location, availability: info.availability)
                bookLocationCacheClient.record(book, holdings)
                return .none

            case let .coverRecovered(id, oldURL, newURL):
                BookFavorites().repairLegacyCover(of: id, from: oldURL, to: newURL)
                return .none

            case let .selectionToggled(id):
                guard state.items.contains(where: { $0.id == id }) else { return .none }
                if let index = state.selectedIDs.firstIndex(of: id) {
                    state.selectedIDs.remove(at: index)
                } else {
                    state.selectedIDs.append(id)
                }
                return .none

            case .removeButtonTapped:
                let removedKeys = Set(state.selectedBooks.map(\.recordKey))
                guard !removedKeys.isEmpty else { return .none }
                let removedCount = BookFavorites().remove(removedKeys)
                if removedCount > 0 {
                    analytics.record(.init(.bookFavoriteChanged, [
                        .action: .text("removed"), .bookCount: .integer(removedCount)
                    ]))
                }
                state.selectedIDs = []
                return .none

            case .addToCartButtonTapped:
                let books = state.selectedBooks
                guard !books.isEmpty else { return .none }
                @Shared(.bookCart) var cartItems
                let storedKeys = Set(cartItems.map(\.book.recordKey))
                let newCount = books.filter { !storedKeys.contains($0.recordKey) }.count
                guard storedKeys.count + newCount <= BookCartItem.maxStoredCount else {
                    state.isCartLimitAlertPresented = true
                    analytics.record(.init(.cartLimitBlocked, [.kind: .text("capacity")]))
                    return .none
                }
                for book in books {
                    if $cartItems.withLock({ $0.add(book, at: now) }) == .added {
                        analytics.record(.init(.cartBookAdded, [.bookRecordID: .text(AnalyticsEvent.bookID(book))]))
                    }
                }
                state.selectedIDs = []
                state.isAddedToCartAlertPresented = true
                return .none

            case .addedToCartAlertDismissed:
                state.isAddedToCartAlertPresented = false
                return .none

            case .goToCartButtonTapped:
                state.isAddedToCartAlertPresented = false
                return .send(.delegate(.showCart))

            case .cartLimitAlertDismissed:
                state.isCartLimitAlertPresented = false
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
                state.libraryInfo[book.id] = .init(location: info.location, availability: info.availability)
            } else {
                if let holdings = cached[book.recordKey] {
                    let location = BookCardLibraryInfo(holdings: holdings).location
                    state.libraryInfo[book.id] = .init(location: location, availability: nil)
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
