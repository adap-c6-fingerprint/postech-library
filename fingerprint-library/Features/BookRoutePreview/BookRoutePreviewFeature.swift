import ComposableArchitecture
import Foundation

/// 소장·서가 조회는 자식 기능에 맡기고, 확정된 입력의 경로 계산과 취소를 관리한다.
@Reducer
struct BookRoutePreviewFeature {
    @ObservableState
    struct State: Equatable {
        var destination: BookRoutePreviewDestination
        var shelfMap: BookShelfMapFeature.State?

        var previewSession: BookNavigationSession?
        var isLoadingRoute = false
        var routeError: String?
        var routeFloorID: UUID?
        var routeRequestID = 0
        var isActive = false

        init(books: [Book] = []) {
            destination = BookRoutePreviewDestination(books: books)
            shelfMap = BookRoutePreviewFeature.makeShelfMapState(for: destination)
        }

        var routeRequest: BookRoutePreviewRequest { .init(state: shelfMap) }

        var readySession: BookNavigationSession? {
            guard let previewSession, case let .ready(map, labels, stops) = routeRequest,
                  previewSession.map == map, previewSession.shelfLabels == labels,
                  previewSession.stops.count == stops.count,
                  previewSession.stops.allSatisfy({ stops.contains($0) }) else { return nil }
            return previewSession
        }

        var orderedBooks: [Book] { readySession?.stops.map(\.book) ?? destination.books }
    }

    enum Action: Equatable {
        case task
        case testModeButtonTapped
        case testModePrepared
        case shelfMap(BookShelfMapFeature.Action)
        case routeRequestChanged(BookRoutePreviewRequest)
        case routeLoaded(requestID: Int, request: BookRoutePreviewRequest, BookNavigationSession)
        case routeFailed(requestID: Int, request: BookRoutePreviewRequest, String)
        case floorSelected(UUID)
        case disappeared
    }

    @Dependency(\.bookRoutePreviewClient) var routeClient
    private nonisolated enum CancelID: Hashable, Sendable { case route }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .task:
                state.isActive = true
                if state.shelfMap == nil { state.shelfMap = Self.makeShelfMapState(for: state.destination) }
                let route: Effect<Action> = .send(.routeRequestChanged(state.routeRequest))
                return state.shelfMap == nil ? route : .merge(route, .send(.shelfMap(.task)))

            case .testModeButtonTapped:
                state.routeRequestID += 1
                state.previewSession = nil
                state.routeError = nil
                state.isLoadingRoute = false
                state.routeFloorID = nil
                state.destination.useTestMode()
                // ifLet은 nil 전환 때 자식 효과를 취소한다. 같은 책의 테스트 전환도 분리한다.
                state.shelfMap = nil
                return .merge(.cancel(id: CancelID.route), .send(.testModePrepared))

            case .testModePrepared:
                guard state.isActive else { return .none }
                state.shelfMap = Self.makeShelfMapState(for: state.destination)
                return .send(.shelfMap(.task))

            case let .routeRequestChanged(request):
                guard state.isActive, request == state.routeRequest else { return .none }
                state.routeRequestID += 1
                let requestID = state.routeRequestID
                state.previewSession = nil
                state.routeError = nil
                state.isLoadingRoute = false
                state.routeFloorID = nil
                if case let .failed(message) = request { state.routeError = message }
                guard case let .ready(map, labels, stops) = request else {
                    return .cancel(id: CancelID.route)
                }
                state.isLoadingRoute = true
                return .run { [routeClient] send in
                    do {
                        try Task.checkCancellation()
                        let session = try await routeClient.load(map, labels, stops)
                        try Task.checkCancellation()
                        await send(.routeLoaded(requestID: requestID, request: request, session))
                    } catch is CancellationError {
                        return
                    } catch {
                        guard !Task.isCancelled else { return }
                        await send(.routeFailed(requestID: requestID, request: request, error.localizedDescription))
                    }
                }
                .cancellable(id: CancelID.route, cancelInFlight: true)

            case let .routeLoaded(requestID, request, session):
                guard state.isActive, requestID == state.routeRequestID, request == state.routeRequest else { return .none }
                state.previewSession = session
                state.isLoadingRoute = false
                return .none

            case let .routeFailed(requestID, request, message):
                guard state.isActive, requestID == state.routeRequestID, request == state.routeRequest else { return .none }
                state.routeError = message
                state.isLoadingRoute = false
                return .none

            case let .floorSelected(id):
                state.routeFloorID = id
                return .none

            case .disappeared:
                state.isActive = false
                state.routeRequestID += 1
                state.isLoadingRoute = false
                let cancel: Effect<Action> = .cancel(id: CancelID.route)
                return state.shelfMap == nil ? cancel : .merge(cancel, .send(.shelfMap(.disappeared)))

            case .shelfMap:
                return .none
            }
        }
        .ifLet(\.shelfMap, action: \.shelfMap) { BookShelfMapFeature() }
        .onChange(of: \.routeRequest) { _, request in
            Reduce { _, _ in .send(.routeRequestChanged(request)) }
        }
    }

    static func makeShelfMapState(for destination: BookRoutePreviewDestination) -> BookShelfMapFeature.State? {
        guard var state = BookShelfMapFeature.State(books: destination.books) else { return nil }
        if destination.isTestMode {
            for item in BookRoutePreviewSample.testItems {
                state.holdings[item.book.id] = .loaded([item.holding])
            }
        }
        return state
    }
}
