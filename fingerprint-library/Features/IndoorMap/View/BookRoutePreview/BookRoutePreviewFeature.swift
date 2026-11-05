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
    @ObservableState
    struct State: Equatable {
        let analyticsID = UUID()
        var analyticsOperation: String { analyticsID.uuidString + ":" + String(requestID) }
        var analyticsIsTest = false
        var previewSession: BookNavigationSession?
        var isLoadingRoute = false
        var routeError: String?
        var requestID = 0
        var startsNavigationWhenLoaded = false
        var navigationSession: BookNavigationSession?
    }
    
    enum Action: Equatable {
        case analyticsTestModeChanged(Bool)
        case requestChanged(BookRoutePreviewRequest)
        case startRequested(BookRoutePreviewRequest)
        case navigationStarted
        case routeLoaded(requestID: Int, BookNavigationSession)
        case routeFailed(requestID: Int, String)
        case reset
        case disappeared
    }
    
    @Dependency(\.bookRoutePreviewClient)
    private var routePreviewClient
    @Dependency(\.date.now) private var now
    @Dependency(\.analyticsClient) private var analytics
    
    private nonisolated enum CancelID: Hashable, Sendable {
        case route
    }
    
    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
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
                    analytics.record(.init(.guidanceRequested, [
                        .operationID: .text(state.analyticsOperation), .bookCount: .integer(stops.count),
                        .isTest: .flag(state.analyticsIsTest || start.source == .simulation || start.source == .replay)
                    ]))
                    analytics.record(.init(.routeCalculationStarted, [
                        .operationID: .text(state.analyticsOperation),
                        .isTest: .flag(state.analyticsIsTest || start.source == .simulation || start.source == .replay)
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
                    .isTest: .flag(state.analyticsIsTest || session.start.source == .simulation || session.start.source == .replay)
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
                    .operationID: .text(state.analyticsOperation), .errorCode: .text("calculation_failed")
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
    }

    private func recordCancellation(_ state: State) {
        guard state.isLoadingRoute else { return }
        analytics.record(.init(.routeCalculationCancelled, [.operationID: .text(state.analyticsOperation)]))
    }
}
