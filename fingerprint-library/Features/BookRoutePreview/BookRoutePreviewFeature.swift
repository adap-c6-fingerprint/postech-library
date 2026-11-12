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

/// 경로 미리보기와 바로 안내 준비.
///
/// 안내할 책의 서가를 조회하고, 출발 위치를 정해 경로를 계산한 뒤 길안내로 넘긴다.
/// 위치는 LocationSessionFeature가 쓰는 @Shared(.indoorLocation)을 읽고, 위치 스트림을 새로 열지 않는다.
@Reducer
struct BookRoutePreviewFeature {
    /// 한 권은 바로 안내하고, 여러 권은 책별 서가를 확인한 뒤 안내한다.
    enum EntryMode: Equatable, Sendable { case preview, direct }

    /// 바로 안내 준비가 끝나지 않을 때 실패 화면으로 바꾸기까지 기다리는 시간.
    static let preparingTimeout: Duration = .seconds(20)

    @ObservableState
    struct State: Equatable {
        /// 안내할 책. 테스트 모드를 고르면 고정 목데이터로 바뀐다.
        var destination: BookRoutePreviewDestination
        let entryMode: EntryMode
        /// 책별 소장처·서가 위치를 조회하는 하위 기능. 지원하지 않는 책 수면 nil이다.
        var shelf: BookShelfMapFeature.State?

        // MARK: 출발 위치

        @Shared(.indoorLocation) var location
        /// 홈 지도에서 사용자가 직접 정해 둔 위치. 미리보기를 여는 시점의 값을 App이 넘긴다.
        let homeManualStart: IndoorPosition?
        /// 이 화면에서 사용자가 직접 지정한 출발 위치. 권한이 없거나 실제 위치가 맞지 않을 때 센서 위치 대신 쓴다.
        var manualStart: IndoorPosition?
        /// 지금 쓸 수 있는 출발 위치. 위치 상태가 바뀌거나 직접 지정할 때 다시 정한다.
        var currentStart: IndoorPosition?
        /// 경로 계산에 쓰는 출발 위치. 처음 위치·층을 받을 때와 다시 계산을 요청할 때만 바뀐다.
        var previewStart: IndoorPosition?
        /// 마지막으로 경로 계산에 넘긴 입력. 같은 입력으로 다시 계산하지 않는다.
        var lastRequest: BookRoutePreviewRequest?

        // MARK: 안내 준비 흐름

        /// 미리보기에서 "바로 안내 시작"을 눌렀는지. 누르기 전에는 위치 권한 알림·출발 위치 설정을 띄우지 않는다.
        var isStartRequested = false
        /// 출발 위치를 직접 정한 직후 그 위치로 경로를 계산해 바로 안내를 시작한다.
        var startsAfterOriginSelected = false
        /// 위치 권한이 없을 때 설정 앱으로 보내거나 직접 설정으로 넘기는 알림.
        var isPermissionAlertPresented = false
        /// 직접 설정으로 넘어가는 중. 지도가 준비되면 출발지 설정 화면을 연다.
        var isPreparingManualOrigin = false
        var isOriginPickerPresented = false
        /// 출발지 설정 화면에 쓸 지도가 준비됐는지. 화면이 홈 지도·서가 지도 중 쓸 수 있는 것을 알린다.
        var isRouteMapReady = false
        /// 준비가 끝나지 않은 채 오래 머문 경우. 사용자가 빠져나갈 수 있게 실패 화면으로 바꾼다.
        var preparingTimedOut = false
        /// 길안내 화면 표시와, 길안내를 마친 뒤 이 화면까지 닫을지.
        var navigationFlow = BookRoutePreviewNavigationState()

        // MARK: 경로 계산

        let analyticsID = UUID()
        var analyticsOperation: String { analyticsID.uuidString + ":" + String(requestID) }
        var analyticsIsTest = false
        var analyticsRequestIsTest = false
        var previewSession: BookNavigationSession?
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

        /// 위치 권한이 없고 직접 정한 출발 위치도 없어, 안내 전에 출발 위치 설정이 필요한 상태.
        var needsStartLocationSetup: Bool { manualStart == nil && !isAuthorized }

        var routeRequest: BookRoutePreviewRequest { .init(state: shelf, start: previewStart) }

        /// 지금 화면의 서가·출발 위치와 맞는 계산 결과. 입력이 바뀐 뒤의 이전 결과는 쓰지 않는다.
        var readySession: BookNavigationSession? {
            guard let previewSession, case let .ready(map, labels, start, stops) = routeRequest,
                  previewSession.map == map, previewSession.shelfLabels == labels,
                  previewSession.start == start,
                  previewSession.matches(candidates: stops) else { return nil }
            return previewSession
        }

        var orderedBooks: [Book] { readySession?.stops.map(\.book) ?? destination.books }

        /// 출발 위치를 정하는 동안에는 경로 오류를 띄우지 않는다. 위치가 없어서 나는 오류라 사용자가 할 일이 아니다.
        var hidesRouteErrorWhileResolvingOrigin: Bool {
            if isPermissionAlertPresented || isOriginPickerPresented || isPreparingManualOrigin { return true }
            // 직접 지정한 출발점으로 계산하다 난 오류는 사용자가 고칠 수 있으므로 보여 준다.
            if manualStart != nil { return false }
            return !isAuthorized
        }

        var showsRouteFailure: Bool {
            (routeError != nil || preparingTimedOut) && !hidesRouteErrorWhileResolvingOrigin
        }

        /// 직접 지정한 위치를 먼저 쓰고, 그다음 최근 센서 위치를 쓴다. 오래된 위치는 쓰지 않는다.
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
        /// 화면이 뜰 때 위치 상태를 읽기 시작하고 안내 준비를 시작한다.
        case task
        case locationUpdated
        case routeMapAvailabilityChanged(Bool)

        /// 여러 권 미리보기의 "바로 안내 시작"
        case startTapped
        /// 미리보기 상세의 "출발"
        case departTapped
        case retryTapped
        case directRetryTapped
        case setOriginManuallyTapped
        case permissionAlertSettingsTapped
        case permissionAlertCancelTapped
        case originConfirmed(IndoorPosition)
        case originPickerCancelled
        case originPickerDismissed
        /// 길안내 화면이 안내를 마쳤다. 길안내가 닫히면 이 화면도 닫는다.
        case navigationEnded
        /// 시스템이 길안내 화면을 닫았다. 안내를 마친 것은 아니므로 이 화면은 남긴다.
        case navigationCoverClosed
        case navigationCoverDismissed
        case preparingTimedOut(requestID: Int)

        case testModeTapped
        case testModeApplied
        /// 지금은 안내할 수 없을 때 책을 책바구니에 담아 두고 화면을 닫는다.
        case addToCartTapped
        case goHomeTapped
        case delegate(Delegate)
        case analyticsTestModeChanged(Bool)
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
                // 소장·서가 조회가 진행되면 경로 계산 입력이 바뀐다.
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
                // 지도가 준비된 뒤에 출발지 설정 화면을 연다. 그동안은 수동 안내 준비 문구를 보여 준다.
                if isReady, state.isPreparingManualOrigin { presentOriginPicker(&state) }
                return .none

            case .startTapped:
                state.isStartRequested = true
                // 출발 위치가 없으면 이때 위치 권한 알림·출발 위치 설정을 시작한다.
                guard !state.needsStartLocationSetup else { return resolveStartAuthorization(&state) }
                return loadRoute(.init(state: state.shelf, start: state.currentStart), startsNavigation: true, state: &state)

            case .departTapped:
                // 미리보기를 보는 동안 이동했을 수 있으므로 탭 시점의 위치로 다시 계산한다.
                return loadRoute(.init(state: state.shelf, start: state.currentStart), startsNavigation: true, state: &state)

            case .retryTapped, .directRetryTapped:
                let permission: Effect<Action> = state.currentStart == nil
                    && state.location.authorization == .notDetermined
                    ? .run { [locationClient] _ in await locationClient.requestPermission() } : .none
                let request = BookRoutePreviewRequest(state: state.shelf, start: state.currentStart)
                guard request == state.routeRequest else {
                    // 출발 위치가 바뀌었으면 그 위치로 다시 계산한다.
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
                // iOS는 위치 권한 화면으로 바로 가는 공개 주소를 주지 않아서 이 앱의 설정 화면을 연다.
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return .none }
                return .run { [openURL] _ in await openURL(url) }

            case .permissionAlertCancelTapped:
                state.isPermissionAlertPresented = false
                state.isPreparingManualOrigin = true
                if state.isRouteMapReady { presentOriginPicker(&state) }
                return .none

            case let .originConfirmed(position):
                // 미리보기에서 "바로 안내 시작"으로 들어왔으면 정한 위치로 바로 안내를 시작한다.
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

            case .navigationEnded:
                state.navigationFlow.navigationEnded()
                return .none

            case .navigationCoverClosed:
                state.navigationFlow.session = nil
                return .none

            case .navigationCoverDismissed:
                // 길안내를 마치고 닫혔으면 미리보기도 닫아 안내를 시작한 화면으로 돌아간다.
                guard state.navigationFlow.presentationDismissed() else { return .none }
                return .run { _ in await dismiss() }

            case let .preparingTimedOut(requestID):
                guard requestID == state.requestID else { return .none }
                state.preparingTimedOut = true
                return .none

            case .testModeTapped:
                state.previewStart = state.currentStart
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
                        return resolveStartAuthorization(&state)
                    }
                    guard state.currentStart != nil else {
                        return loadRoute(.failed(IndoorRoutingError.invalidPosition.localizedDescription),
                                         startsNavigation: true, state: &state)
                    }
                    state.navigationFlow.start(session)
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
                // 위치가 없어 경로가 실패했는데 아무것도 안내하지 않으면 준비 문구만 남는다. 그 상태를 만들지 않는다.
                return .merge(reconcile(&state), resolveStartAuthorization(&state))

            case .reset:
                recordCancellation(state)
                state.requestID += 1
                state.previewSession = nil
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
    }

    /// 공유 위치 상태가 바뀔 때마다 알린다. 위치 센서 스트림은 LocationSessionFeature만 연다.
    private func observeLocation() -> Effect<Action> {
        .run { send in
            @Shared(.indoorLocation) var location
            for await _ in $location.publisher.values {
                await send(.locationUpdated)
            }
        }
        .cancellable(id: CancelID.location, cancelInFlight: true)
    }

    /// 경로 계산 입력이 바뀌었으면 다시 계산한다.
    ///
    /// 처음 위치·층을 받으면 그 위치로 계산하고, 계산을 마치거나 실패한 뒤에는 위치를 받을 때마다 다시 계산하지 않는다.
    private func reconcile(_ state: inout State) -> Effect<Action> {
        if state.previewSession == nil, !state.isLoadingRoute,
           state.previewStart == nil || state.previewStart?.floorOrdinal == nil {
            state.previewStart = state.currentStart
        }
        let request = state.routeRequest
        guard request != state.lastRequest else { return .none }
        state.lastRequest = request
        switch state.entryMode {
        case .direct:
            // 소장·지도 로딩이 끝난 시점의 현재 위치에서 안내를 시작한다.
            return loadRoute(.init(state: state.shelf, start: state.currentStart), startsNavigation: true, state: &state)
        case .preview where state.startsAfterOriginSelected:
            state.startsAfterOriginSelected = false
            return loadRoute(request, startsNavigation: true, state: &state)
        case .preview:
            return loadRoute(request, startsNavigation: false, state: &state)
        }
    }

    /// 위치 권한이 없으면 설정 앱으로 보내거나 출발 위치를 직접 지정하게 하는 알림을 띄운다.
    ///
    /// iOS는 한 번 거부한 뒤에는 시스템 권한 창을 다시 띄우지 않는다. 그래서 권한 요청 대신
    /// 이 앱의 설정 화면으로 보내는 버튼을 둔다.
    private func resolveStartAuthorization(_ state: inout State) -> Effect<Action> {
        // 미리보기는 "바로 안내 시작"을 누른 뒤에만 출발 위치 설정을 시작한다.
        guard state.entryMode == .direct || state.isStartRequested,
              state.manualStart == nil, !state.isOriginPickerPresented, !state.isPermissionAlertPresented,
              !state.isPreparingManualOrigin, state.navigationFlow.session == nil,
              !state.isAuthorized else { return .none }
        state.isPermissionAlertPresented = true
        return .none
    }

    private func presentOriginPicker(_ state: inout State) {
        state.isPreparingManualOrigin = false
        state.isOriginPickerPresented = true
    }

    /// 경로를 계산한다. 이전 계산은 취소하고, 늦게 온 결과는 요청 번호로 버린다.
    private func loadRoute(
        _ request: BookRoutePreviewRequest, startsNavigation: Bool, state: inout State
    ) -> Effect<Action> {
        recordCancellation(state)
        state.requestID += 1
        state.previewSession = nil
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

            let calculation: Effect<Action> = .run { [routePreviewClient] send in
                do {
                    try Task.checkCancellation()
                    let session = try await routePreviewClient.load(map, labels, start, stops)
                    try Task.checkCancellation()
                    await send(.routeLoaded(requestID: requestID, session))
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

    /// 바로 안내에서 오류도 경로도 없이 준비 문구만 남는 상태를 끝낸다. 요청이 바뀌면 다시 센다.
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
