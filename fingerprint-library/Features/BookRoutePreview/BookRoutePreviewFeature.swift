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
    nonisolated static let locatingTimeout: Duration = .seconds(5)

    @ObservableState
    struct State: Equatable {
        var destination: BookRoutePreviewDestination
        let entryMode: EntryMode
        var shelf: BookShelfMapFeature.State?

        @Shared(.indoorLocation) var location
        var manualStart: IndoorPosition?
        var currentStart: IndoorPosition?
        var previewStart: IndoorPosition?
        var lastRequest: BookRoutePreviewRequest?
        var startDecision: RouteStartDecision?
        var hasLocatingTimedOut = false
        var isLocatingTimerRunning = false
        var hasRequestedHoldings = false

        var isStartRequested = false
        var startsAfterOriginSelected = false
        var isPermissionAlertPresented = false
        var isPreparingManualOrigin = false
        var isOriginPickerPresented = false
        var isRouteMapReady = false
        var preparingTimedOut = false
        var isRetryingDirectNavigation = false
        var retryingRouteError: RouteFailure?
        @Presents var navigation: BookNavigationFeature.State?
        var returnsToOriginAfterNavigation = false

        let analyticsID: UUID = { @Dependency(\.uuid) var uuid; return uuid() }()
        var analyticsOperation: String { analyticsID.uuidString + ":" + String(requestID) }
        var analyticsRequestIsTest = false
        var previewPlan: RoutePlan?
        var isLoadingRoute = false
        var routeError: RouteFailure?
        var requestID = 0
        var startsNavigationWhenLoaded = false

        init(books: [Book] = [], entryMode: EntryMode = .preview) {
            destination = BookRoutePreviewDestination(books: books)
            self.entryMode = entryMode
            shelf = Self.makeShelfState(for: destination)
        }

        static func makeShelfState(for destination: BookRoutePreviewDestination) -> BookShelfMapFeature.State? {
            BookShelfMapFeature.State(books: destination.books)
        }

        var isAuthorized: Bool { location.authorization.isAuthorized }

        var needsStartLocationSetup: Bool {
            guard manualStart == nil else { return false }
            switch startDecision {
            case .needsOrigin: return true
            case nil: return !isAuthorized
            case .current, .entrance, .locating: return false
            }
        }

        var startNotice: String? {
            guard manualStart == nil else { return nil }
            return startDecision?.notice
        }

        var isPreviewFromEntrance: Bool {
            manualStart == nil && previewStart?.source == .manual
        }

        var entranceApproach: LibraryEntranceApproach? {
            guard manualStart == nil,
                  case let .entrance(entrance, .outside) = startDecision,
                  let position = location.position, let map = shelf?.map.map else { return nil }
            return .init(position: position, entrance: entrance, map: map)
        }

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
            if navigation != nil || returnsToOriginAfterNavigation { return true }
            if isPermissionAlertPresented || isOriginPickerPresented || isPreparingManualOrigin { return true }
            if manualStart != nil { return false }
            switch startDecision {
            case .needsOrigin, .locating: return true
            case .current, .entrance: return false
            case nil: return !isAuthorized
            }
        }

        var showsRouteFailure: Bool {
            (routeError != nil || preparingTimedOut || isRetryingDirectNavigation) && !hidesRouteErrorWhileResolvingOrigin
        }

        var failureMessage: RouteFailure? {
            isRetryingDirectNavigation ? retryingRouteError : routeError
        }

        var isShelfLoading: Bool {
            guard let shelf else { return false }
            return shelf.map.isLoading || shelf.map.isLoadingShelfLabels
                || shelf.books.contains { shelf.holdings[$0.id] == .loading }
        }

        mutating func refreshCurrentStart(at now: Date) {
            if let start = manualStart {
                currentStart = start
                startDecision = nil
                return
            }
            guard let map = shelf?.map.map else {
                currentStart = nil
                startDecision = nil
                return
            }
            var decision = RouteStartPolicy().decide(
                position: location.position, isAuthorized: isAuthorized, map: map, now: now)
            if decision == .locating, hasLocatingTimedOut {
                decision = .needsOrigin(.noPosition)
            }
            startDecision = decision
            currentStart = decision.startPosition
        }
    }

    enum Action {
        case shelf(BookShelfMapFeature.Action)
        case task
        case locationUpdated
        case routeMapAvailabilityChanged(Bool)

        case startTapped
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
        case locatingTimedOut

        case addToCartTapped
        case goHomeTapped
        case delegate(Delegate)
        case routeLoaded(requestID: Int, RoutePlan)
        case routeFailed(requestID: Int, RouteFailure)
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
        case locatingTimeout
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .shelf:
                state.refreshCurrentStart(at: now)
                return .merge(reconcile(&state), resolveStartAuthorization(&state), syncLocatingTimeout(&state))

            case .task:
                guard !state.returnsToOriginAfterNavigation else { return .none }
                state.refreshCurrentStart(at: now)
                return .merge(
                    observeLocation(),
                    reconcile(&state),
                    resolveStartAuthorization(&state),
                    syncLocatingTimeout(&state)
                )

            case .locationUpdated:
                state.refreshCurrentStart(at: now)
                return .merge(reconcile(&state), resolveStartAuthorization(&state), syncLocatingTimeout(&state))

            case .locatingTimedOut:
                state.isLocatingTimerRunning = false
                state.hasLocatingTimedOut = true
                state.refreshCurrentStart(at: now)
                return .merge(reconcile(&state), resolveStartAuthorization(&state))

            case let .routeMapAvailabilityChanged(isReady):
                state.isRouteMapReady = isReady
                if isReady, state.isPreparingManualOrigin { presentOriginPicker(&state) }
                return .none

            case .startTapped:
                state.isStartRequested = true
                state.refreshCurrentStart(at: now)
                guard !state.needsStartLocationSetup else { return resolveStartAuthorization(&state) }
                return loadRoute(.init(state: state.shelf, start: state.currentStart), startsNavigation: true, state: &state)

            case .directRetryTapped where state.showsRouteFailure:
                state.isRetryingDirectNavigation = true
                state.retryingRouteError = state.routeError
                state.refreshCurrentStart(at: now)
                let reloads = shelfReloads(state)
                guard !reloads.isEmpty else { return retryRoute(startsNavigation: true, state: &state) }
                return .merge(permissionRequest(state), restartPreparingTimeout(&state), .merge(reloads))

            case .retryTapped, .directRetryTapped:
                return retryRoute(startsNavigation: action.is(\.directRetryTapped), state: &state)

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
                return .merge(reconcile(&state), syncLocatingTimeout(&state))

            case .originPickerCancelled:
                state.isOriginPickerPresented = false
                return .run { _ in await dismiss() }

            case .originPickerDismissed:
                state.isOriginPickerPresented = false
                state.isPreparingManualOrigin = false
                return .none

            case .navigation(.presented(.setOriginManuallyTapped)):
                state.navigation = nil
                state.isPreparingManualOrigin = true
                return .none

            case .navigation(.presented):
                guard state.navigation?.exitReason != nil else { return .none }
                state.navigation = nil
                state.returnsToOriginAfterNavigation = true
                state.routeError = nil
                state.preparingTimedOut = false
                return .merge(.cancel(id: CancelID.preparingTimeout), .cancel(id: CancelID.locatingTimeout),
                              .cancel(id: CancelID.route), .cancel(id: CancelID.location))

            case .navigation(.dismiss):
                return .none

            case .navigationCoverDismissed:
                if state.isPreparingManualOrigin {
                    if state.isRouteMapReady { presentOriginPicker(&state) }
                    return .none
                }
                guard state.returnsToOriginAfterNavigation else { return .none }
                return .run { _ in await dismiss() }

            case let .preparingTimedOut(requestID):
                guard requestID == state.requestID, state.navigation == nil,
                      !state.returnsToOriginAfterNavigation, state.previewPlan == nil else { return .none }
                state.preparingTimedOut = true
                endDirectRetry(&state)
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

            case let .routeLoaded(requestID, routePlan):
                guard state.isLoadingRoute,
                      state.requestID == requestID else {
                    return .none
                }

                state.isLoadingRoute = false
                state.refreshCurrentStart(at: now)
                state.previewPlan = routePlan
                state.preparingTimedOut = false
                endDirectRetry(&state)
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
                        state.routeError = .routing(.invalidPosition)
                        return .merge(reconcile(&state), resolveStartAuthorization(&state), syncLocatingTimeout(&state))
                    }
                    guard state.currentStart != nil else {
                        return loadRoute(.failed(.routing(.invalidPosition)),
                                         startsNavigation: true, state: &state)
                    }
                    if state.navigation == nil, !state.returnsToOriginAfterNavigation {
                        var navigation = BookNavigationFeature.State(
                            routePlan: routePlan, usesManualOrigin: state.manualStart != nil,
                            startsAtEntrance: state.entranceApproach != nil)
                        if let notice = state.startNotice { navigation.startNotice = notice }
                        state.navigation = navigation
                    }
                }
                return .concatenate(.cancel(id: CancelID.preparingTimeout),
                                    .merge(reconcile(&state), resolveStartAuthorization(&state)))

            case let .routeFailed(requestID, message):
                guard state.isLoadingRoute,
                      state.requestID == requestID else {
                    return .none
                }

                state.isLoadingRoute = false
                state.routeError = message
                endDirectRetry(&state)
                analytics.record(.init(.routeCalculationFailed, [
                    .operationID: .text(state.analyticsOperation), .errorCode: .text("calculation_failed"),
                    .isTest: .flag(state.analyticsRequestIsTest)
                ]))
                state.startsNavigationWhenLoaded = false
                return .merge(reconcile(&state), resolveStartAuthorization(&state))

            case .disappeared:
                recordCancellation(state)
                state.requestID += 1
                state.isLoadingRoute = false
                state.startsNavigationWhenLoaded = false
                state.isLocatingTimerRunning = false
                endDirectRetry(&state)
                return .merge(
                    .cancel(id: CancelID.route),
                    .cancel(id: CancelID.location),
                    .cancel(id: CancelID.preparingTimeout),
                    .cancel(id: CancelID.locatingTimeout)
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
        guard state.navigation == nil, !state.returnsToOriginAfterNavigation,
              !state.isPreparingManualOrigin, !state.isOriginPickerPresented else { return .none }
        let holdings = requestHoldingsIfReady(&state)
        if state.isPreviewFromEntrance,
           case let .current(position) = state.startDecision {
            state.previewStart = position
        }
        if case let .entrance(position, _) = state.startDecision,
           state.previewStart?.coordinate != position.coordinate || state.previewStart?.floorOrdinal != position.floorOrdinal {
            state.previewStart = position
        }
        if state.currentStart == nil { state.previewStart = nil }
        if state.previewPlan == nil, !state.isLoadingRoute,
           state.previewStart == nil || state.previewStart?.floorOrdinal == nil
                || state.previewStart?.isRecent(at: now) == false {
            state.previewStart = state.currentStart
        }
        let request = state.routeRequest
        guard request != state.lastRequest else { return holdings }
        state.lastRequest = request
        let route: Effect<Action>
        switch state.entryMode {
        case .direct:
            route = loadRoute(.init(state: state.shelf, start: state.currentStart), startsNavigation: true, state: &state)
        case .preview where state.startsAfterOriginSelected:
            if case .ready = request { state.startsAfterOriginSelected = false }
            route = loadRoute(request, startsNavigation: true, state: &state)
        case .preview:
            route = loadRoute(request, startsNavigation: false, state: &state)
        }
        return .merge(holdings, route)
    }

    private func requestHoldingsIfReady(_ state: inout State) -> Effect<Action> {
        guard let start = state.currentStart, start.isRecent(at: now),
              let map = state.shelf?.map.map, state.shelf?.map.loadError == nil,
              map.floors.contains(where: { $0.ordinal == start.floorOrdinal }),
              !state.hasRequestedHoldings else { return .none }
        state.hasRequestedHoldings = true
        return .send(.shelf(.loadMissingHoldings))
    }

    private func resolveStartAuthorization(_ state: inout State) -> Effect<Action> {
        guard state.entryMode == .direct || state.isStartRequested,
              state.manualStart == nil,
              !state.isOriginPickerPresented, !state.isPermissionAlertPresented,
              !state.isPreparingManualOrigin, state.navigation == nil,
              !state.returnsToOriginAfterNavigation else { return .none }
        switch state.startDecision {
        case .needsOrigin(.notAuthorized):
            state.isPermissionAlertPresented = true
        case .needsOrigin:
            state.isPreparingManualOrigin = true
            if state.isRouteMapReady { presentOriginPicker(&state) }
        case nil where !state.isAuthorized:
            state.isPermissionAlertPresented = true
        case nil, .current, .entrance, .locating:
            break
        }
        if state.isPermissionAlertPresented || state.isPreparingManualOrigin { endDirectRetry(&state) }
        return .none
    }

    private func presentOriginPicker(_ state: inout State) {
        endDirectRetry(&state)
        state.isPreparingManualOrigin = false
        state.isOriginPickerPresented = true
    }

    private func retryRoute(startsNavigation: Bool, state: inout State) -> Effect<Action> {
        state.refreshCurrentStart(at: now)
        let permission = permissionRequest(state)
        let request = BookRoutePreviewRequest(state: state.shelf, start: state.currentStart)
        guard request == state.routeRequest else {
            state.previewStart = state.currentStart
            return .merge(permission, reconcile(&state))
        }
        return .merge(permission, loadRoute(request, startsNavigation: startsNavigation, state: &state))
    }

    private func permissionRequest(_ state: State) -> Effect<Action> {
        guard state.currentStart == nil, state.location.authorization == .notDetermined else { return .none }
        return .run { [locationClient] _ in await locationClient.requestPermission() }
    }

    private func shelfReloads(_ state: State) -> [Effect<Action>] {
        guard let shelf = state.shelf else { return [] }
        var reloads: [Effect<Action>] = []
        if shelf.map.map == nil || shelf.map.loadError != nil || shelf.map.shelfLabelError != nil {
            reloads.append(.send(.shelf(.map(.retryTapped))))
        }
        for book in shelf.books {
            guard case .failed = shelf.holdings[book.id] else { continue }
            reloads.append(.send(.shelf(.retryHoldingsTapped(book.id))))
        }
        return reloads
    }

    private func endDirectRetry(_ state: inout State) {
        state.isRetryingDirectNavigation = false
        state.retryingRouteError = nil
    }

    private func loadRoute(
        _ request: BookRoutePreviewRequest, startsNavigation: Bool, state: inout State
    ) -> Effect<Action> {
        guard state.navigation == nil, !state.returnsToOriginAfterNavigation else { return .none }
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
            if !state.isShelfLoading { endDirectRetry(&state) }
            return .merge(.cancel(id: CancelID.route), timeout, resolveStartAuthorization(&state))

        case let .ready(map, labels, start, stops):
            guard start.isRecent(at: now) else {
                state.routeError = .routing(.invalidPosition)
                state.startsNavigationWhenLoaded = false
                endDirectRetry(&state)
                return .merge(.cancel(id: CancelID.route), timeout, resolveStartAuthorization(&state))
            }
            state.isLoadingRoute = true
            state.analyticsRequestIsTest = start.source == .replay
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
                    await send(.routeFailed(requestID: requestID, RouteFailure(error: error)))
                }
            }
            .cancellable(id: CancelID.route, cancelInFlight: true)
            return .merge(calculation, timeout)
        }
    }

    private func syncLocatingTimeout(_ state: inout State) -> Effect<Action> {
        guard state.startDecision == .locating, state.navigation == nil,
              !state.returnsToOriginAfterNavigation else {
            guard state.isLocatingTimerRunning else { return .none }
            state.isLocatingTimerRunning = false
            return .cancel(id: CancelID.locatingTimeout)
        }
        guard !state.isLocatingTimerRunning else { return .none }
        state.isLocatingTimerRunning = true
        return .run { [clock] send in
            try await clock.sleep(for: Self.locatingTimeout)
            await send(.locatingTimedOut)
        }
        .cancellable(id: CancelID.locatingTimeout, cancelInFlight: true)
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
