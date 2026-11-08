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
        var items: [BookFavoriteItem] = []
        var libraryInfo: [Book.ID: BookBasketFeature.LibraryInfo] = [:]
        var selectedIDs: [Book.ID] = []
        // 장바구니에 담거나 삭제할 책을 고른 순서대로 보관한다.
        var isAddedToBasketAlertPresented = false
        var isBasketLimitAlertPresented = false

        @Presents var basket: BookBasketFeature.State?

        var sections: [BookFavoriteSection] {
            BookFavoriteSection.grouped(items, calendar: .current)
        }

        var selectedBooks: [Book] {
            selectedIDs.compactMap { id in items.first { $0.id == id }?.book }
        }
        // 아직 찜 목록에 남아 있는 선택 책만 고른 순서대로 돌려준다.
    }

    enum Action {
        case task
        case loadLibraryInfo
        case libraryInfoLoaded(Book.ID, [BookHolding])
        case coverRecovered(Book.ID, URL, URL)
        case selectionToggled(Book.ID)
        case removeButtonTapped
        case addToBasketButtonTapped
        case addedToBasketAlertDismissed
        case goToBasketButtonTapped
        case basketLimitAlertDismissed
        case basket(PresentationAction<BookBasketFeature.Action>)
        case delegate(Delegate)

        @CasePathable
        enum Delegate: Equatable {
            case favoritesChanged(Set<[String?]>)
            // 다른 화면의 하트 상태와 지도 표시를 맞추도록 바뀐 찜 키를 알린다.
            case basketChanged
            // 다른 화면의 장바구니 권수를 맞추도록 알린다.
        }
    }

    @Dependency(\.bookFavoritesClient) var bookFavoritesClient
    @Dependency(\.bookBasketClient) var bookBasketClient
    @Dependency(\.bookHoldingsClient) var bookHoldingsClient
    @Dependency(\.bookLocationCacheClient) var bookLocationCacheClient
    @Dependency(\.date.now) var now
    @Dependency(\.analyticsClient) private var analytics

    private nonisolated enum CancelID: Hashable, Sendable {
        case libraryInfo
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .task:
                state.items = bookFavoritesClient.loadItems()
                let itemIDs = Set(state.items.map(\.id))
                state.selectedIDs.removeAll { !itemIDs.contains($0) }
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
                bookFavoritesClient.repairLegacyCover(id, oldURL, newURL)
                state.items = bookFavoritesClient.loadItems()
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
                var keys = bookFavoritesClient.load()
                let removedCount = keys.intersection(removedKeys).count
                // 다른 화면에서 바꾼 찜도 보존하도록 최신 저장 목록에서 뺀다.
                keys.subtract(removedKeys)
                bookFavoritesClient.save(keys)
                if removedCount > 0 {
                    analytics.record(.init(.bookFavoriteChanged, [
                        .action: .text("removed"), .bookCount: .integer(removedCount)
                    ]))
                }
                state.items = bookFavoritesClient.loadItems()
                state.selectedIDs = []
                return .send(.delegate(.favoritesChanged(keys)))

            case .addToBasketButtonTapped:
                let books = state.selectedBooks
                guard !books.isEmpty else { return .none }
                let storedKeys = Set(bookBasketClient.load().map(\.book.recordKey))
                let newCount = books.filter { !storedKeys.contains($0.recordKey) }.count
                guard storedKeys.count + newCount <= BookBasketItem.maxStoredCount else {
                    state.isBasketLimitAlertPresented = true
                    analytics.record(.init(.basketLimitBlocked, [.kind: .text("capacity")]))
                    // 일부만 담기지 않도록 한도를 넘으면 한 권도 담지 않는다.
                    return .none
                }
                for book in books {
                    if bookBasketClient.add(book, at: now) == .added {
                        analytics.record(.init(.basketBookAdded, [.bookRecordID: .text(AnalyticsEvent.bookID(book))]))
                    }
                }
                state.selectedIDs = []
                // 찜 목록에는 그대로 두고 선택만 해제한다.
                state.isAddedToBasketAlertPresented = true
                return .send(.delegate(.basketChanged))

            case .addedToBasketAlertDismissed:
                state.isAddedToBasketAlertPresented = false
                return .none

            case .goToBasketButtonTapped:
                state.isAddedToBasketAlertPresented = false
                state.basket = BookBasketFeature.State()
                return .none

            case .basketLimitAlertDismissed:
                state.isBasketLimitAlertPresented = false
                return .none

            case .basket, .delegate:
                return .none
            }
        }
        .ifLet(\.$basket, action: \.basket) {
            BookBasketFeature()
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
