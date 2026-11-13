import Foundation
import ComposableArchitecture

@Reducer
struct HomeFeature {
    @ObservableState
    struct State: Equatable {
        var recommendedBooks: [Book] = []
        var popularBooks: [Book] = []
        var departmentRecommendations: DepartmentRecommendationsState = .loading
        @Shared(.userProfile) var userProfile: UserProfile?
        var displayedProfile: UserProfile?
        var hasSyncedProfile = false
        var isProfileComplete: Bool {
            guard let userProfile else { return false }
            return RecommendationDataset.AffiliationPath(key: userProfile.affiliationKey) != nil
                && !userProfile.interests.isEmpty
        }
        var departmentName: String { userProfile?.departmentName ?? "" }
        var isRecommendationExpanded = true
        var showsKulumiCovers = false
        var libraryInfo: [Book.ID: LibraryInfoState] = [:]
        var libraryInfoGeneration = 0
        var libraryInfoPending: [Book.ID] = []
        var libraryInfoInFlight: Set<Book.ID> = []
        var libraryInfoUpdatedAt: [Book.ID: Date] = [:]

        var openedDetailCoverURL: URL?

        var recommendationCount: Int {
            let count = DatasetRecommendation.displayCount
            return recommendedBooks.isEmpty ? count : min(recommendedBooks.count, count)
        }

        var booksForLibraryInfo: [Book] {
            guard case let .loaded(books) = departmentRecommendations else { return popularBooks }
            let previewIDs = Set(popularBooks.map(\.id))
            return popularBooks + books.filter { !previewIDs.contains($0.id) }
        }

        var recommendationErrorMessage: String? = nil
        var recommendationCoverFiles: [Book.ID: URL] = [:]
        var popularBooksErrorMessage: String? = nil
        var popularBooksPreparation: CarouselPreparation = .idle
        var popularBooksRefreshID: UUID?
        var isRefreshingPopularBooks = false
        var canRefreshPopularBooks: Bool {
            isProfileComplete && !popularBooks.isEmpty && userProfile?.affiliationKey == displayedProfile?.affiliationKey
        }
        var recommendationSessionID: UUID?
        var isLoadingRecommendations = false
        var isPreparingRecommendations = false
        var recommendationLoadMode: RecommendationLoadMode = .restore
        var carouselPreparation: CarouselPreparation = .idle
        var isRefreshingRecommendations: Bool {
            isPreparingRecommendations && recommendationLoadMode == .carouselRefresh
        }
        var nextRecommendationsSavedAt: Date?
    }

    enum RecommendationLoadMode {
        case restore
        case profileChanged
        case carouselRefresh
    }

    enum CarouselPreparation: Equatable {
        case idle
        case loading(UUID)
        case finished(Result<[Book], CarouselFailure>)
    }

    enum CarouselFailure: Error, Equatable {
        case insufficientBooks
        case preparationFailed

        var message: String {
            switch self {
            case .insufficientBooks: "새 추천 6권을 찾지 못했어요."
            case .preparationFailed: "새 추천을 불러오지 못했어요."
            }
        }
    }

    enum LibraryInfoState: Equatable {
        case loading
        case loaded(BookCardLibraryInfo)
        case unavailable
        case failed
    }

    enum DepartmentRecommendationsState: Equatable {
        case loading
        case loaded([Book])
        case failed(String)
    }

    enum Action {
        case task
        case recommendationSessionStarted
        case recommendationNearEnd
        case recommendationEndReached
        case carouselPreparationFinished(UUID, Result<[Book], CarouselFailure>)
        case retryRecommendationsButtonTapped
        case recommendationsRestored(UUID, CachedRecommendations?)
        case recommendationsLoaded(UUID, CachedRecommendations)
        case popularBooksLoaded([Book])
        case popularBooksNearEnd
        case popularBooksRefreshRequested
        case popularBooksPreparationFinished(UUID, Result<[Book], CarouselFailure>)
        case departmentRecommendationsRequested
        case departmentRecommendationsLoaded([Book])
        case departmentRecommendationsFailed(String)
        case loadLibraryInfo
        case libraryInfoLoaded(generation: Int, Book.ID, [BookHolding])
        case libraryInfoFailed(generation: Int, Book.ID)
        case libraryInfoCancelled
        case upcomingCoversChanged( [URL] )

        case bookSelected(Book)
        case cartButtonTapped
        case favoritesButtonTapped
        case profileButtonTapped
        case departmentRecommendationsButtonTapped
        case delegate(Delegate)

        case recommendationsFailed(UUID, String)
        case popularBooksFailed(String)

        @CasePathable
        enum Delegate: Equatable {
            case showDetail(Book, cachedCoverURL: URL?)
            case showCart
            case showFavorites
            case showMyPage
            case showDepartmentRecommendations
        }
    }

    @Dependency(\.homeRecommendationForYouClient) var homeRecommendationForYouClient
    @Dependency(\.bookCoverClient) var bookCoverClient
    @Dependency(\.departmentPopularBooksClient)
    var departmentPopularBooksClient

    @Dependency(\.bookHoldingsClient) var bookHoldingsClient
    @Dependency(\.bookLocationCacheClient) var bookLocationCacheClient
    @Dependency(\.uuid) var uuid
    @Dependency(\.analyticsClient) private var analytics
    @Dependency(\.date.now) var now

    private nonisolated enum CancelID: Hashable, Sendable {
        case recommendationSession
        case carouselPreparation
        case departmentRecommendations
        case libraryInfo
        case popularBooks
        case popularBooksPreparation
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .task:
                let sync = syncWithProfile(state: &state)
                var effects = [sync.reload]

                if state.recommendedBooks.isEmpty && state.recommendationSessionID == nil {
                    effects.append(.send(.recommendationSessionStarted))
                }

                if state.popularBooks.isEmpty {
                    state.popularBooksErrorMessage = nil
                    effects.append(loadPopularBooks(affiliationKey: state.userProfile?.affiliationKey ?? []))
                }

                return .concatenate(sync.cancel, .merge(effects))

            case .recommendationSessionStarted:
                return startRecommendationSession(state: &state, mode: .restore)

            case .recommendationNearEnd:
                guard !state.showsKulumiCovers, !state.recommendedBooks.isEmpty,
                      state.carouselPreparation == .idle else { return .none }
                return prepareCarouselReplacement(state: &state)

            case .recommendationEndReached:
                guard !state.showsKulumiCovers, !state.recommendedBooks.isEmpty,
                      !state.isRefreshingRecommendations else { return .none }
                let sessionID = beginRecommendationSession(state: &state, mode: .carouselRefresh)
                if case let .finished(result) = state.carouselPreparation {
                    return applyCarouselReplacement(
                        result, sessionID: sessionID, retaining: displayedRecommendationCovers(state)
                    )
                }
                let prepare = state.carouselPreparation == .idle ? prepareCarouselReplacement(state: &state) : .none
                return .merge(.cancel(id: CancelID.recommendationSession), prepare)

            case let .carouselPreparationFinished(id, result):
                guard state.carouselPreparation == .loading(id) else { return .none }
                state.carouselPreparation = .finished(result)
                guard state.isRefreshingRecommendations, let sessionID = state.recommendationSessionID else { return .none }
                return applyCarouselReplacement(
                    result, sessionID: sessionID, retaining: displayedRecommendationCovers(state)
                )

            case .retryRecommendationsButtonTapped:
                guard !state.isPreparingRecommendations else { return .none }
                let mode = state.recommendationLoadMode
                return .send(mode == .carouselRefresh ? .recommendationEndReached : .recommendationSessionStarted)

            case let .recommendationsRestored(sessionID, cached):
                guard state.recommendationSessionID == sessionID else { return .none }
                if let cached {
                    let booksChanged = state.recommendedBooks.map(\.id) != cached.books.map(\.id)
                    analytics.record(.init(.recommendationLoadCompleted, [
                        .kind: .text("restored"), .bookCount: .integer(cached.books.count)
                    ]))
                    state.recommendedBooks = cached.books
                    state.recommendationCoverFiles = cached.coverFiles
                    state.isLoadingRecommendations = false
                    if booksChanged {
                        state.carouselPreparation = .idle
                        return .cancel(id: CancelID.carouselPreparation)
                    }
                }
                return .none

            case let .recommendationsLoaded(sessionID, prepared):
                guard state.recommendationSessionID == sessionID else { return .none }
                let isCarouselRefresh = state.recommendationLoadMode == .carouselRefresh
                analytics.record(.init(.recommendationLoadCompleted, [
                    .kind: .text(isCarouselRefresh ? "carousel_refresh" : "prepared_for_next_visit"),
                    .bookCount: .integer(prepared.books.count)
                ]))
                state.isLoadingRecommendations = false
                state.isPreparingRecommendations = false
                state.nextRecommendationsSavedAt = prepared.savedAt
                if isCarouselRefresh || state.recommendedBooks.isEmpty {
                    state.recommendedBooks = prepared.books
                    state.recommendationCoverFiles = prepared.coverFiles
                }
                if isCarouselRefresh { state.carouselPreparation = .idle }
                state.recommendationErrorMessage = nil
                return .none

            case let .recommendationsFailed(sessionID, message):
                guard state.recommendationSessionID == sessionID else { return .none }
                analytics.record(.init(.recommendationFailed, [.errorCode: .text("preparation_failed")]))
                state.isLoadingRecommendations = false
                state.isPreparingRecommendations = false
                if state.recommendationLoadMode == .carouselRefresh { state.carouselPreparation = .idle }
                state.recommendationErrorMessage = message
                return .none

            case let .popularBooksLoaded(books):
                state.popularBooks = books
                state.popularBooksErrorMessage = books.isEmpty
                    ? "인기 도서를 찾지 못했어요."
                    : nil
                return .none

            case let .popularBooksFailed(message):
                state.popularBooksErrorMessage = message
                return .none

            case .popularBooksNearEnd:
                guard state.canRefreshPopularBooks, state.popularBooksPreparation == .idle else { return .none }
                return preparePopularBooksReplacement(state: &state)

            case .popularBooksRefreshRequested:
                guard state.canRefreshPopularBooks, !state.isRefreshingPopularBooks else { return .none }
                state.popularBooksRefreshID = uuid()
                state.popularBooksErrorMessage = nil
                if case let .finished(result) = state.popularBooksPreparation {
                    applyPopularBooksReplacement(result, state: &state)
                    return .none
                }
                state.isRefreshingPopularBooks = true
                return state.popularBooksPreparation == .idle ? preparePopularBooksReplacement(state: &state) : .none

            case let .popularBooksPreparationFinished(id, result):
                guard state.popularBooksPreparation == .loading(id) else { return .none }
                guard state.userProfile?.affiliationKey == state.displayedProfile?.affiliationKey else {
                    state.popularBooksPreparation = .idle
                    state.popularBooksRefreshID = nil
                    state.isRefreshingPopularBooks = false
                    return .none
                }
                if state.isRefreshingPopularBooks {
                    applyPopularBooksReplacement(result, state: &state)
                } else {
                    state.popularBooksPreparation = .finished(result)
                }
                return .none

            case .departmentRecommendationsRequested:
                let sync = syncWithProfile(state: &state)
                if case .loaded = state.departmentRecommendations {
                    return .concatenate(sync.cancel, sync.reload)
                }
                state.departmentRecommendations = .loading
                let affiliationKey = state.userProfile?.affiliationKey ?? []
                let load: Effect<Action> = .run { [departmentPopularBooksClient] send in
                    do {
                        let books = try await departmentPopularBooksClient.fetchAll(affiliationKey)
                        try Task.checkCancellation()
                        await send(.departmentRecommendationsLoaded(books))
                    } catch {
                        guard !Task.isCancelled else { return }
                        await send(.departmentRecommendationsFailed(error.localizedDescription))
                    }
                }
                .cancellable(id: CancelID.departmentRecommendations, cancelInFlight: true)
                return .concatenate(sync.cancel, .merge(sync.reload, load))

            case let .departmentRecommendationsLoaded(books):
                state.departmentRecommendations = .loaded(books)
                return .none

            case let .departmentRecommendationsFailed(message):
                state.departmentRecommendations = .failed(message)
                return .none

            case .loadLibraryInfo:
                return loadLibraryInfo(state: &state)

            case let .libraryInfoLoaded(generation, bookID, holdings):
                guard state.libraryInfoGeneration == generation,
                      state.libraryInfoInFlight.remove(bookID) != nil else { return .none }
                if let book = state.booksForLibraryInfo.first(where: { $0.id == bookID }) {
                    state.libraryInfo[bookID] = .loaded(BookCardLibraryInfo(holdings: holdings))
                    state.libraryInfoUpdatedAt[bookID] = now
                    bookLocationCacheClient.record(book, holdings)
                }
                return startNextLibraryInfoRequests(state: &state)

            case let .libraryInfoFailed(generation, bookID):
                guard state.libraryInfoGeneration == generation,
                      state.libraryInfoInFlight.remove(bookID) != nil else { return .none }
                if state.booksForLibraryInfo.contains(where: { $0.id == bookID }) {
                    state.libraryInfo[bookID] = .failed
                    state.libraryInfoUpdatedAt[bookID] = nil
                }
                return startNextLibraryInfoRequests(state: &state)

            case .libraryInfoCancelled:
                return cancelLibraryInfo(state: &state)

            case let .upcomingCoversChanged(urls):
                return .run { [bookCoverClient] _ in
                    await bookCoverClient.prefetch(urls)
                }
                

            case let .bookSelected(book):
                analytics.record(.init(.recommendationSelected, [.bookRecordID: .text(AnalyticsEvent.bookID(book))]))
                let coverURL = state.recommendationCoverFiles[book.id]
                state.openedDetailCoverURL = coverURL
                return .send(.delegate(.showDetail(book, cachedCoverURL: coverURL)))

            case .cartButtonTapped:
                return .send(.delegate(.showCart))

            case .favoritesButtonTapped:
                return .send(.delegate(.showFavorites))

            case .profileButtonTapped:
                return .send(.delegate(.showMyPage))

            case .departmentRecommendationsButtonTapped:
                return .send(.delegate(.showDepartmentRecommendations))

            case .delegate:
                return .none
            }
        }
    }

    private func loadLibraryInfo(state: inout State) -> Effect<Action> {
        let books = state.booksForLibraryInfo
        let visibleIDs = Set(books.map(\.id))
        state.libraryInfo = state.libraryInfo.filter { visibleIDs.contains($0.key) }
        state.libraryInfoUpdatedAt = state.libraryInfoUpdatedAt.filter { visibleIDs.contains($0.key) }
        state.libraryInfoPending.removeAll { !visibleIDs.contains($0) }

        for book in books {
            guard !state.libraryInfoInFlight.contains(book.id) else { continue }
            if case .loaded = state.libraryInfo[book.id],
               let updatedAt = state.libraryInfoUpdatedAt[book.id],
               now.timeIntervalSince(updatedAt) < 60 {
                continue
            }
            guard BookHoldingsClient.recordID(for: book) != nil else {
                state.libraryInfo[book.id] = .unavailable
                continue
            }
            state.libraryInfo[book.id] = .loading
            if !state.libraryInfoPending.contains(book.id) {
                state.libraryInfoPending.append(book.id)
            }
        }
        if state.libraryInfoInFlight.isEmpty && !state.libraryInfoPending.isEmpty {
            state.libraryInfoGeneration += 1
        }
        return startNextLibraryInfoRequests(state: &state)
    }

    private func startNextLibraryInfoRequests(state: inout State) -> Effect<Action> {
        var effects: [Effect<Action>] = []
        while state.libraryInfoInFlight.count < 3 && !state.libraryInfoPending.isEmpty {
            let bookID = state.libraryInfoPending.removeFirst()
            guard let book = state.booksForLibraryInfo.first(where: { $0.id == bookID }),
                  let recordID = BookHoldingsClient.recordID(for: book) else { continue }
            state.libraryInfoInFlight.insert(bookID)
            let generation = state.libraryInfoGeneration
            effects.append(.run { [bookHoldingsClient] send in
                do {
                    let holdings = try await bookHoldingsClient.fetch(recordID)
                    try Task.checkCancellation()
                    await send(.libraryInfoLoaded(generation: generation, bookID, holdings))
                } catch {
                    guard !Task.isCancelled else { return }
                    await send(.libraryInfoFailed(generation: generation, bookID))
                }
            }.cancellable(id: CancelID.libraryInfo))
        }
        return .merge(effects)
    }

    private func cancelLibraryInfo(state: inout State) -> Effect<Action> {
        state.libraryInfoGeneration += 1
        state.libraryInfoPending = []
        state.libraryInfoInFlight = []
        return .cancel(id: CancelID.libraryInfo)
    }

    private func syncWithProfile(state: inout State) -> (cancel: Effect<Action>, reload: Effect<Action>) {
        let current = state.userProfile
        guard state.hasSyncedProfile else {
            state.hasSyncedProfile = true
            state.displayedProfile = current
            return (.none, .none)
        }
        let previous = state.displayedProfile
        guard let current, current != previous else { return (.none, .none) }
        state.displayedProfile = current
        var cancels: [Effect<Action>] = []
        var reload: Effect<Action> = .none

        if current.affiliationKey != previous?.affiliationKey {
            state.popularBooks = []
            state.popularBooksErrorMessage = nil
            state.popularBooksPreparation = .idle
            state.popularBooksRefreshID = nil
            state.isRefreshingPopularBooks = false
            state.departmentRecommendations = .loading
            if !state.libraryInfoInFlight.isEmpty || !state.libraryInfoPending.isEmpty {
                cancels.append(cancelLibraryInfo(state: &state))
            }
            state.libraryInfo = [:]
            state.libraryInfoUpdatedAt = [:]
            cancels.append(.cancel(id: CancelID.popularBooks))
            cancels.append(.cancel(id: CancelID.popularBooksPreparation))
            cancels.append(.cancel(id: CancelID.departmentRecommendations))
        }

        if current.interests != previous?.interests {
            state.recommendedBooks = []
            state.recommendationCoverFiles = [:]
            reload = startRecommendationSession(state: &state, mode: .profileChanged)
        }
        return (.merge(cancels), reload)
    }

    private func startRecommendationSession(state: inout State, mode: RecommendationLoadMode) -> Effect<Action> {
        state.carouselPreparation = .idle
        let sessionID = beginRecommendationSession(state: &state, mode: mode)
        return .merge(
            .cancel(id: CancelID.carouselPreparation),
            loadRecommendations(sessionID: sessionID, retaining: displayedRecommendationCovers(state), restoresCache: mode == .restore)
        )
    }

    private func beginRecommendationSession(state: inout State, mode: RecommendationLoadMode) -> UUID {
        let sessionID = uuid()
        state.recommendationSessionID = sessionID
        state.recommendationLoadMode = mode
        state.isLoadingRecommendations = mode != .carouselRefresh
        state.isPreparingRecommendations = true
        state.nextRecommendationsSavedAt = nil
        state.recommendationErrorMessage = nil
        return sessionID
    }

    private func displayedRecommendationCovers(_ state: State) -> [URL] {
        Array(state.recommendationCoverFiles.values)
            + [state.openedDetailCoverURL].compactMap { $0 }
    }

    private func loadRecommendations(sessionID: UUID, retaining covers: [URL], restoresCache: Bool) -> Effect<Action> {
        .run { [homeRecommendationForYouClient] send in
            do {
                if restoresCache {
                    let cached = await homeRecommendationForYouClient.restore(covers)
                    try Task.checkCancellation()
                    await send(.recommendationsRestored(sessionID, cached))
                }
                let prepared = try await homeRecommendationForYouClient.refresh(
                    DatasetRecommendation.displayCount, covers
                )
                try Task.checkCancellation()
                await send(.recommendationsLoaded(sessionID, prepared))
            } catch is CancellationError {
                return
            } catch HomeRecommendationForYouError.empty {
                await send(.recommendationsFailed(sessionID, "추천 도서를 찾지 못했어요. 다시 시도해 주세요."))
            } catch {
                guard !Task.isCancelled else { return }
                await send(.recommendationsFailed(sessionID, "추천 도서를 준비하지 못했어요. 다시 시도해 주세요."))
            }
        }
        .cancellable(id: CancelID.recommendationSession, cancelInFlight: true)
    }

    private func prepareCarouselReplacement(state: inout State) -> Effect<Action> {
        let id = uuid()
        let displayedBooks = state.recommendedBooks
        state.carouselPreparation = .loading(id)
        return .run { [homeRecommendationForYouClient, bookCoverClient] send in
            do {
                let books = try await homeRecommendationForYouClient.prepareReplacement(
                    DatasetRecommendation.displayCount, displayedBooks
                )
                try Task.checkCancellation()
                await send(.carouselPreparationFinished(id, .success(books)))
                await bookCoverClient.prefetch(books.prefix(2).compactMap(\.imageURL))
            } catch is CancellationError {
                return
            } catch HomeRecommendationForYouError.insufficientReplacements {
                await send(.carouselPreparationFinished(id, .failure(.insufficientBooks)))
            } catch {
                guard !Task.isCancelled else { return }
                await send(.carouselPreparationFinished(id, .failure(.preparationFailed)))
            }
        }
        .cancellable(id: CancelID.carouselPreparation, cancelInFlight: true)
    }

    private func applyCarouselReplacement(
        _ result: Result<[Book], CarouselFailure>, sessionID: UUID, retaining covers: [URL]
    ) -> Effect<Action> {
        .run { [homeRecommendationForYouClient] send in
            do {
                let prepared = try await homeRecommendationForYouClient.saveReplacement(result.get(), covers)
                try Task.checkCancellation()
                await send(.recommendationsLoaded(sessionID, prepared))
            } catch is CancellationError {
                return
            } catch let failure as CarouselFailure {
                await send(.recommendationsFailed(sessionID, failure.message))
            } catch {
                guard !Task.isCancelled else { return }
                await send(.recommendationsFailed(sessionID, CarouselFailure.preparationFailed.message))
            }
        }
        .cancellable(id: CancelID.recommendationSession, cancelInFlight: true)
    }

    private func loadPopularBooks(affiliationKey: [String]) -> Effect<Action> {
        .run { [departmentPopularBooksClient] send in
            do {
                let books = try await departmentPopularBooksClient.fetch(
                    affiliationKey, DatasetRecommendation.displayCount
                )
                try Task.checkCancellation()
                await send(.popularBooksLoaded(books))
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                await send(.popularBooksFailed(error.localizedDescription))
            }
        }
        .cancellable(id: CancelID.popularBooks, cancelInFlight: true)
    }

    private func preparePopularBooksReplacement(state: inout State) -> Effect<Action> {
        let id = uuid()
        let affiliationKey = state.displayedProfile?.affiliationKey ?? []
        let excludedKeys = Set(state.popularBooks.flatMap { DatasetRecommendation.identityKeys(of: $0) })
        state.popularBooksPreparation = .loading(id)
        return .run { [departmentPopularBooksClient, bookCoverClient] send in
            do {
                let books = try await departmentPopularBooksClient.prepareReplacement(
                    affiliationKey, DatasetRecommendation.displayCount, excludedKeys
                )
                try Task.checkCancellation()
                guard books.count == DatasetRecommendation.displayCount else {
                    await send(.popularBooksPreparationFinished(id, .failure(.insufficientBooks)))
                    return
                }
                await send(.popularBooksPreparationFinished(id, .success(books)))
                await bookCoverClient.prefetch(books.prefix(2).compactMap(\.imageURL))
            } catch {
                guard !Task.isCancelled else { return }
                await send(.popularBooksPreparationFinished(id, .failure(.preparationFailed)))
            }
        }
        .cancellable(id: CancelID.popularBooksPreparation, cancelInFlight: true)
    }

    private func applyPopularBooksReplacement(_ result: Result<[Book], CarouselFailure>, state: inout State) {
        state.popularBooksPreparation = .idle
        state.isRefreshingPopularBooks = false
        switch result {
        case let .success(books): state.popularBooks = books
        case let .failure(error): state.popularBooksErrorMessage = error.message
        }
    }
}
