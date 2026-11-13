//
//  BookRoutePreviewFeature.swift
//  fingerprint-library
//
//  Created by Youngmin Cho on 10/30/26.
//

import Combine
import ComposableArchitecture
import Foundation
import UIKit

@Reducer
struct BookRoutePreviewFeature {
    enum EntryMode: Equatable, Sendable { case preview, direct }

    nonisolated static let preparingTimeout: Duration = .seconds(20)

    @ObservableState
    struct State: Equatable {
        var destination: BookRoutePreviewDestination
        let entryMode: EntryMode
        var shelf: BookShelfMapFeature.State?

        @Shared(.indoorLocation) var location
        let homeManualStart: IndoorPosition?
        var manualStart: IndoorPosition?
        var currentStart: IndoorPosition?
        var previewStart: IndoorPosition?
        var lastRequest: BookRoutePreviewRequest?

        var isStartRequested = false
        var startsAfterOriginSelected = false
        var isPermissionAlertPresented = false
        var isPreparingManualOrigin = false
        var isOriginPickerPresented = false
        var isRouteMapReady = false
        var preparingTimedOut = false
        @Presents var navigation: BookNavigationFeature.State?
        var returnsToOriginAfterNavigation = false

        let analyticsID: UUID = { @Dependency(\.uuid) var uuid; return uuid() }()
        var analyticsOperation: String { analyticsID.uuidString + ":" + String(requestID) }
        var analyticsIsTest = false
        var analyticsRequestIsTest = false
        var previewPlan: RoutePlan?
        var isLoadingRoute = false
        var routeError: String?
        var requestID = 0
        var startsNavigationWhenLoaded = false

        init(books: [Book] = [], entryMode: EntryMode = .preview, homeManualStart: IndoorPosition? = nil) {
            destination = BookRoutePreviewDestination(books: books)
            self.entryMode = entryMode
            self.homeManualStart = homeManualStart
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

        var isAuthorized: Bool { location.authorization.isAuthorized }

        var needsStartLocationSetup: Bool { manualStart == nil && !isAuthorized }

        var routeRequest: BookRoutePreviewRequest { .init(state: shelf, start: previewStart) }

        var readySession: RoutePlan? {
            guard let previewPlan, case let .ready(map, labels, start, stops) = routeRequest,
                  previewPlan.map == map, previewPlan.shelfLabels == labels,
                  previewPlan.start == start,
                  previewPlan.matches(candidates: stops) else { return nil }
            return previewPlan
        }

        var orderedBooks: [Book] { readySession?.stops.map(\.book) ?? destination.books }

        var hidesRouteErrorWhileResolvingOrigin: Bool {
            if isPermissionAlertPresented || isOriginPickerPresented || isPreparingManualOrigin { return true }
            if manualStart != nil { return false }
            return !isAuthorized
        }

        var showsRouteFailure: Bool {
            (routeError != nil || preparingTimedOut) && !hidesRouteErrorWhileResolvingOrigin
        }

        mutating func refreshCurrentStart(at now: Date) {
            if let manualStart {
                currentStart = manualStart
                return
            }
            guard let position = homeManualStart ?? location.position,
                  position.source == .manual || isAuthorized,
                  position.isRecent(at: now) else {
                currentStart = nil
                return
            }
            currentStart = position
        }
    }

    enum Action: Equatable {
        case shelf(BookShelfMapFeature.Action)
        case task
        case locationUpdated
        case routeMapAvailabilityChanged(Bool)

        case startTapped
        case departTapped
        case retryTapped
        case directRetryTapped
        case setOriginManuallyTapped
        case permissionAlertSettingsTapped
        case permissionAlertCancelTapped
        case originConfirmed(IndoorMapCoordinate, floorOrdinal: Int)
        case originPickerCancelled
        case originPickerDismissed
        case navigation(PresentationAction<BookNavigationFeature.Action>)
        case navigationCoverDismissed
        case preparingTimedOut(requestID: Int)

        case testModeTapped
        case testModeApplied
        case addToCartTapped
        case goHomeTapped
        case delegate(Delegate)
        case analyticsTestModeChanged(Bool)
        case routeLoaded(requestID: Int, RoutePlan)
        case routeFailed(requestID: Int, String)
        case reset
        case disappeared

        @CasePathable
        enum Delegate: Equatable {
            case goHomeRequested
        }
    }

    @Dependency(\.routePlanningClient)
    private var routePlanningClient
    @Dependency(\.indoorLocationClient) private var locationClient
    @Dependency(\.date.now) private var now
    @Dependency(\.continuousClock) private var clock
    @Dependency(\.analyticsClient) private var analytics
    @Dependency(\.dismiss) private var dismiss
    @Dependency(\.openURL) private var openURL

    private nonisolated enum CancelID: Hashable, Sendable {
        case route
        case location
        case preparingTimeout
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .shelf:
                return reconcile(&state)

            case .task:
                state.refreshCurrentStart(at: now)
                return .merge(
                    observeLocation(),
                    reconcile(&state),
                    resolveStartAuthorization(&state)
                )

            case .locationUpdated:
                state.refreshCurrentStart(at: now)
                return .merge(reconcile(&state), resolveStartAuthorization(&state))

            case let .routeMapAvailabilityChanged(isReady):
                state.isRouteMapReady = isReady
                if isReady, state.isPreparingManualOrigin { presentOriginPicker(&state) }
                return .none

            case .startTapped:
                state.isStartRequested = true
                guard !state.needsStartLocationSetup else { return resolveStartAuthorization(&state) }
                return loadRoute(.init(state: state.shelf, start: state.currentStart), startsNavigation: true, state: &state)

            case .departTapped:
                return loadRoute(.init(state: state.shelf, start: state.currentStart), startsNavigation: true, state: &state)

            case .retryTapped, .directRetryTapped:
                let permission: Effect<Action> = state.currentStart == nil
                    && state.location.authorization == .notDetermined
                    ? .run { [locationClient] _ in await locationClient.requestPermission() } : .none
                let request = BookRoutePreviewRequest(state: state.shelf, start: state.currentStart)
                guard request == state.routeRequest else {
                    state.previewStart = state.currentStart
                    return .merge(permission, reconcile(&state))
                }
                let startsNavigation = action == .directRetryTapped
                return .merge(permission, loadRoute(request, startsNavigation: startsNavigation, state: &state))

            case .setOriginManuallyTapped:
                presentOriginPicker(&state)
                return .none

            case .permissionAlertSettingsTapped:
                state.isPermissionAlertPresented = false
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return .none }
                return .run { [openURL] _ in await openURL(url) }

            case .permissionAlertCancelTapped:
                state.isPermissionAlertPresented = false
                state.isPreparingManualOrigin = true
                if state.isRouteMapReady { presentOriginPicker(&state) }
                return .none

            case let .originConfirmed(coordinate, floorOrdinal):
                let position = IndoorPosition(
                    coordinate: coordinate, floorOrdinal: floorOrdinal, horizontalAccuracy: nil,
                    timestamp: now, source: .manual)
                if state.entryMode == .preview, state.isStartRequested { state.startsAfterOriginSelected = true }
                state.manualStart = position
                state.isOriginPickerPresented = false
                state.previewStart = position
                state.refreshCurrentStart(at: now)
                return reconcile(&state)

            case .originPickerCancelled:
                state.isOriginPickerPresented = false
                return .run { _ in await dismiss() }

            case .originPickerDismissed:
                state.isOriginPickerPresented = false
                state.isPreparingManualOrigin = false
                return .none

            case .navigation(.presented):
                guard state.navigation?.exitReason != nil else { return .none }
                state.navigation = nil
                state.returnsToOriginAfterNavigation = true
                return .none

            case .navigation(.dismiss):
                return .none

            case .navigationCoverDismissed:
                guard state.returnsToOriginAfterNavigation else { return .none }
                state.returnsToOriginAfterNavigation = false
                return .run { _ in await dismiss() }

            case let .preparingTimedOut(requestID):
                guard requestID == state.requestID else { return .none }
                state.preparingTimedOut = true
                return .none

            case .testModeTapped:
                state.previewStart = state.currentStart
                return .concatenate(
                    .send(.shelf(.map(.disappeared))),
                    .send(.reset),
                    .send(.analyticsTestModeChanged(true)),
                    .send(.testModeApplied)
                )

            case .testModeApplied:
                state.destination.useTestMode()
                state.shelf = State.makeShelfState(for: state.destination)
                return reconcile(&state)

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

            case let .routeLoaded(requestID, routePlan):
                guard state.isLoadingRoute,
                      state.requestID == requestID else {
                    return .none
                }

                state.isLoadingRoute = false
                state.previewPlan = routePlan
                analytics.record(.init(.routeCalculationCompleted, [
                    .operationID: .text(state.analyticsOperation), .navigationID: .text(routePlan.id.uuidString),
                    .distanceM: .decimal(routePlan.route.distanceMeters), .bookCount: .integer(routePlan.stops.count),
                    .stepCount: .integer(routePlan.guidance.stepCount),
                    .isTest: .flag(state.analyticsRequestIsTest)
                ]))
                if state.startsNavigationWhenLoaded {
                    state.startsNavigationWhenLoaded = false
                    guard routePlan.start.isRecent(at: now) else {
                        state.previewPlan = nil
                        state.routeError = IndoorRoutingError.invalidPosition.localizedDescription
                        return resolveStartAuthorization(&state)
                    }
                    guard state.currentStart != nil else {
                        return loadRoute(.failed(IndoorRoutingError.invalidPosition.localizedDescription),
                                         startsNavigation: true, state: &state)
                    }
                    if state.navigation == nil, !state.returnsToOriginAfterNavigation {
                        var navigation = BookNavigationFeature.State(routePlan: routePlan)
                        navigation.analyticsIsTest = state.destination.isTestMode
                        state.navigation = navigation
                    }
                }
                return .merge(reconcile(&state), resolveStartAuthorization(&state))

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
                return .merge(reconcile(&state), resolveStartAuthorization(&state))

            case .reset:
                recordCancellation(state)
                state.requestID += 1
                state.previewPlan = nil
                state.isLoadingRoute = false
                state.routeError = nil
                state.startsNavigationWhenLoaded = false
                state.lastRequest = nil
                return .merge(.cancel(id: CancelID.route), restartPreparingTimeout(&state))

            case .disappeared:
                recordCancellation(state)
                state.requestID += 1
                state.isLoadingRoute = false
                state.startsNavigationWhenLoaded = false
                return .merge(
                    .cancel(id: CancelID.route),
                    .cancel(id: CancelID.location),
                    .cancel(id: CancelID.preparingTimeout)
                )
            }
        }
        .ifLet(\.shelf, action: \.shelf) { BookShelfMapFeature() }
        .ifLet(\.$navigation, action: \.navigation) { BookNavigationFeature() }
    }

    private func observeLocation() -> Effect<Action> {
        .run { send in
            @Shared(.indoorLocation) var location
            for await _ in $location.publisher.values {
                await send(.locationUpdated)
            }
        }
        .cancellable(id: CancelID.location, cancelInFlight: true)
    }

    private func reconcile(_ state: inout State) -> Effect<Action> {
        if state.previewPlan == nil, !state.isLoadingRoute,
           state.previewStart == nil || state.previewStart?.floorOrdinal == nil {
            state.previewStart = state.currentStart
        }
        let request = state.routeRequest
        guard request != state.lastRequest else { return .none }
        state.lastRequest = request
        switch state.entryMode {
        case .direct:
            return loadRoute(.init(state: state.shelf, start: state.currentStart), startsNavigation: true, state: &state)
        case .preview where state.startsAfterOriginSelected:
            state.startsAfterOriginSelected = false
            return loadRoute(request, startsNavigation: true, state: &state)
        case .preview:
            return loadRoute(request, startsNavigation: false, state: &state)
        }
    }

    private func resolveStartAuthorization(_ state: inout State) -> Effect<Action> {
        guard state.entryMode == .direct || state.isStartRequested,
              state.manualStart == nil, !state.isOriginPickerPresented, !state.isPermissionAlertPresented,
              !state.isPreparingManualOrigin, state.navigation == nil,
              !state.isAuthorized else { return .none }
        state.isPermissionAlertPresented = true
        return .none
    }

    private func presentOriginPicker(_ state: inout State) {
        state.isPreparingManualOrigin = false
        state.isOriginPickerPresented = true
    }

    private func loadRoute(
        _ request: BookRoutePreviewRequest, startsNavigation: Bool, state: inout State
    ) -> Effect<Action> {
        recordCancellation(state)
        state.requestID += 1
        state.previewPlan = nil
        state.isLoadingRoute = false
        state.routeError = nil
        state.startsNavigationWhenLoaded = startsNavigation
        let timeout = restartPreparingTimeout(&state)

        switch request {
        case .waiting:
            state.startsNavigationWhenLoaded = false
            return .merge(.cancel(id: CancelID.route), timeout)

        case .failed(let message):
            state.routeError = message
            state.startsNavigationWhenLoaded = false
            return .merge(.cancel(id: CancelID.route), timeout, resolveStartAuthorization(&state))

        case let .ready(map, labels, start, stops):
            guard start.isRecent(at: now) else {
                state.routeError = IndoorRoutingError.invalidPosition.localizedDescription
                state.startsNavigationWhenLoaded = false
                return .merge(.cancel(id: CancelID.route), timeout, resolveStartAuthorization(&state))
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

            let calculation: Effect<Action> = .run { [routePlanningClient] send in
                do {
                    try Task.checkCancellation()
                    let routePlan = try await routePlanningClient.plan(map, labels, start, stops)
                    try Task.checkCancellation()
                    await send(.routeLoaded(requestID: requestID, routePlan))
                } catch is CancellationError {
                    return
                } catch {
                    guard !Task.isCancelled else { return }
                    await send(.routeFailed(requestID: requestID, error.localizedDescription))
                }
            }
            .cancellable(id: CancelID.route, cancelInFlight: true)
            return .merge(calculation, timeout)
        }
    }

    private func restartPreparingTimeout(_ state: inout State) -> Effect<Action> {
        state.preparingTimedOut = false
        guard state.entryMode == .direct else { return .cancel(id: CancelID.preparingTimeout) }
        let requestID = state.requestID
        return .run { [clock] send in
            try await clock.sleep(for: BookRoutePreviewFeature.preparingTimeout)
            await send(.preparingTimedOut(requestID: requestID))
        }
        .cancellable(id: CancelID.preparingTimeout, cancelInFlight: true)
    }

    private func recordCancellation(_ state: State) {
        guard state.isLoadingRoute else { return }
        analytics.record(.init(.routeCalculationCancelled, [
            .operationID: .text(state.analyticsOperation), .isTest: .flag(state.analyticsRequestIsTest)
        ]))
    }
}
