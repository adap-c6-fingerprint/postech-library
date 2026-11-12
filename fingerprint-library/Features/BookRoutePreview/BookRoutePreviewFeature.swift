//
//  BookRoutePreviewFeature.swift
//  fingerprint-library
//
//  Created by Youngmin Cho on 10/30/26.
//

import ComposableArchitecture
import Foundation

@Reducer
struct BookRoutePreviewFeature {
    /// 한 권은 바로 안내하고, 여러 권은 책별 서가를 확인한 뒤 안내한다.
    enum EntryMode: Equatable, Sendable { case preview, direct }

    @ObservableState
    struct State: Equatable {
        /// 안내할 책. 테스트 모드를 고르면 고정 목데이터로 바뀐다.
        var destination: BookRoutePreviewDestination
        let entryMode: EntryMode
        /// 책별 소장처·서가 위치를 조회하는 하위 기능. 지원하지 않는 책 수면 nil이다.
        var shelf: BookShelfMapFeature.State?
        let analyticsID = UUID()
        var analyticsOperation: String { analyticsID.uuidString + ":" + String(requestID) }
        var analyticsIsTest = false
        var analyticsRequestIsTest = false
        var previewSession: BookNavigationSession?
        var isLoadingRoute = false
        var routeError: String?
        var requestID = 0
        var startsNavigationWhenLoaded = false
        var navigationSession: BookNavigationSession?

        init(books: [Book] = [], entryMode: EntryMode = .preview) {
            destination = BookRoutePreviewDestination(books: books)
            self.entryMode = entryMode
            shelf = Self.makeShelfState(for: destination)
        }

        static func makeShelfState(for destination: BookRoutePreviewDestination) -> BookShelfMapFeature.State? {
            guard var state = BookShelfMapFeature.State(books: destination.books) else { return nil }
            if destination.isTestMode {
                for item in BookRoutePreviewSample.testItems {
                    state.holdings[item.book.id] = .loaded([item.holding])
                }
            }
            return state
        }
    }
    
    enum Action: Equatable {
        case shelf(BookShelfMapFeature.Action)
        case testModeTapped
        case testModeApplied
        /// 지금은 안내할 수 없을 때 책을 책바구니에 담아 두고 화면을 닫는다.
        case addToCartTapped
        case goHomeTapped
        case delegate(Delegate)
        case analyticsTestModeChanged(Bool)
        case requestChanged(BookRoutePreviewRequest)
        case startRequested(BookRoutePreviewRequest)
        case navigationStarted
        case routeLoaded(requestID: Int, BookNavigationSession)
        case routeFailed(requestID: Int, String)
        case reset
        case disappeared

        enum Delegate: Equatable {
            /// 미리보기와 그 아래 상세·책바구니 화면까지 닫고 홈 지도 탭으로 돌아간다.
            case goHomeRequested
        }
    }
    
    @Dependency(\.bookRoutePreviewClient)
    private var routePreviewClient
    @Dependency(\.date.now) private var now
    @Dependency(\.analyticsClient) private var analytics
    @Dependency(\.dismiss) private var dismiss
    
    private nonisolated enum CancelID: Hashable, Sendable {
        case route
    }
    
    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .shelf:
                return .none

            case .testModeTapped:
                // 이전 도서의 지도·소장 조회를 끝낸 뒤 고정 목데이터로 바꾼다.
                return .concatenate(
                    .send(.shelf(.map(.disappeared))),
                    .send(.reset),
                    .send(.analyticsTestModeChanged(true)),
                    .send(.testModeApplied)
                )

            case .testModeApplied:
                state.destination.useTestMode()
                state.shelf = State.makeShelfState(for: state.destination)
                return .none

            case .addToCartTapped:
                @Shared(.bookCart) var cartItems
                let books = state.destination.books
                $cartItems.withLock { items in
                    for book in books { items.add(book, at: now) }
                }
                return .run { _ in await dismiss() }

            case .goHomeTapped:
                return .send(.delegate(.goHomeRequested))

            case .delegate:
                return .none

            case let .analyticsTestModeChanged(value):
                state.analyticsIsTest = value
                return .none
            case .requestChanged(let request), .startRequested(let request):
                recordCancellation(state)
                state.requestID += 1
                state.previewSession = nil
                state.isLoadingRoute = false
                state.routeError = nil
                state.navigationSession = nil
                if case .startRequested = action {
                    state.startsNavigationWhenLoaded = true
                } else {
                    state.startsNavigationWhenLoaded = false
                }
                
                switch request {
                case .waiting:
                    state.startsNavigationWhenLoaded = false
                    return .cancel(id: CancelID.route)
                    
                case .failed(let message):
                    state.routeError = message
                    state.startsNavigationWhenLoaded = false
                    return .cancel(id: CancelID.route)
                    
                case let .ready(map, labels, start, stops):
                    guard start.isRecent(at: now) else {
                        state.routeError = IndoorRoutingError.invalidPosition.localizedDescription
                        state.startsNavigationWhenLoaded = false
                        return .cancel(id: CancelID.route)
                    }
                    state.isLoadingRoute = true
                    state.analyticsRequestIsTest = state.analyticsIsTest || start.source == .replay
                    analytics.record(.init(.guidanceRequested, [
                        .operationID: .text(state.analyticsOperation), .bookCount: .integer(stops.count),
                        .isTest: .flag(state.analyticsRequestIsTest)
                    ]))
                    analytics.record(.init(.routeCalculationStarted, [
                        .operationID: .text(state.analyticsOperation),
                        .isTest: .flag(state.analyticsRequestIsTest)
                    ]))
                    let requestID = state.requestID
                    
                    return .run { [routePreviewClient] send in
                        do {
                            try Task.checkCancellation()
                            
                            let session = try await routePreviewClient.load(
                                map, labels, start, stops
                            )
                            
                            try Task.checkCancellation()
                            await send(.routeLoaded(
                                requestID: requestID,
                                session
                            ))
                        } catch is CancellationError {
                            return
                        } catch {
                            guard !Task.isCancelled else { return }
                            
                            await send(.routeFailed(
                                requestID: requestID,
                                error.localizedDescription
                            ))
                        }
                    }
                    .cancellable(
                        id: CancelID.route,
                        cancelInFlight: true
                    )
                }
                
            case let .routeLoaded(requestID, session):
                guard state.isLoadingRoute,
                      state.requestID == requestID else {
                    return .none
                }
                
                state.isLoadingRoute = false
                state.previewSession = session
                analytics.record(.init(.routeCalculationCompleted, [
                    .operationID: .text(state.analyticsOperation), .navigationID: .text(session.id.uuidString),
                    .distanceM: .decimal(session.route.distanceMeters), .bookCount: .integer(session.stops.count),
                    .stepCount: .integer(session.guidance.stepCount),
                    .isTest: .flag(state.analyticsRequestIsTest)
                ]))
                if state.startsNavigationWhenLoaded {
                    state.startsNavigationWhenLoaded = false
                    guard session.start.isRecent(at: now) else {
                        state.previewSession = nil
                        state.routeError = IndoorRoutingError.invalidPosition.localizedDescription
                        return .none
                    }
                    state.navigationSession = session
                }
                return .none
                
            case let .routeFailed(requestID, message):
                guard state.isLoadingRoute,
                      state.requestID == requestID else {
                    return .none
                }
                
                state.isLoadingRoute = false
                state.routeError = message
                analytics.record(.init(.routeCalculationFailed, [
                    .operationID: .text(state.analyticsOperation), .errorCode: .text("calculation_failed"),
                    .isTest: .flag(state.analyticsRequestIsTest)
                ]))
                state.startsNavigationWhenLoaded = false
                return .none

            case .navigationStarted:
                state.navigationSession = nil
                return .none
                
            case .reset:
                recordCancellation(state)
                state.requestID += 1
                state.previewSession = nil
                state.isLoadingRoute = false
                state.routeError = nil
                state.startsNavigationWhenLoaded = false
                state.navigationSession = nil
                return .cancel(id: CancelID.route)
                
            case .disappeared:
                recordCancellation(state)
                state.requestID += 1
                state.isLoadingRoute = false
                state.startsNavigationWhenLoaded = false
                state.navigationSession = nil
                return .cancel(id: CancelID.route)
            }
        }
        .ifLet(\.shelf, action: \.shelf) { BookShelfMapFeature() }
    }

    private func recordCancellation(_ state: State) {
        guard state.isLoadingRoute else { return }
        analytics.record(.init(.routeCalculationCancelled, [
            .operationID: .text(state.analyticsOperation), .isTest: .flag(state.analyticsRequestIsTest)
        ]))
    }
}
