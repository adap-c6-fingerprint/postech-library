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
        var previewSession: BookNavigationSession?
        var isLoadingRoute = false
        var routeError: String?
        var requestID = 0
    }
    
    enum Action: Equatable {
        case requestChanged(BookRoutePreviewRequest)
        case routeLoaded(requestID: Int, BookNavigationSession)
        case routeFailed(requestID: Int, String)
        case reset
        case disappeared
    }
    
    @Dependency(\.bookRoutePreviewClient)
    private var routePreviewClient
    
    private nonisolated enum CancelID: Hashable, Sendable {
        case route
    }
    
    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .requestChanged(let request):
                state.requestID += 1
                state.previewSession = nil
                state.isLoadingRoute = false
                state.routeError = nil
                
                switch request {
                case .waiting:
                    return .cancel(id: CancelID.route)
                    
                case .failed(let message):
                    state.routeError = message
                    return .cancel(id: CancelID.route)
                    
                case let .ready(map, labels, stops):
                    state.isLoadingRoute = true
                    let requestID = state.requestID
                    
                    return .run { [routePreviewClient] send in
                        do {
                            try Task.checkCancellation()
                            
                            let session = try await routePreviewClient.load(
                                map, labels, stops
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
                return .none
                
            case let .routeFailed(requestID, message):
                guard state.isLoadingRoute,
                      state.requestID == requestID else {
                    return .none
                }
                
                state.isLoadingRoute = false
                state.routeError = message
                return .none
                
            case .reset:
                state.requestID += 1
                state.previewSession = nil
                state.isLoadingRoute = false
                state.routeError = nil
                return .cancel(id: CancelID.route)
                
            case .disappeared:
                state.requestID += 1
                state.isLoadingRoute = false
                return .cancel(id: CancelID.route)
            }
        }
    }
}
