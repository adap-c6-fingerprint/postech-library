import ComposableArchitecture
import Foundation

// 실시간 안내 위치 품질 진단(실험 브랜치 전용).
// 기록이 꺼져 있으면 안내 상태를 바꾸지 않고, 기록 중일 때만 진단 상태와 기록을 갱신한다.
extension BookNavigationFeature {
    struct Diagnostics: Equatable {
        var isPanelPresented = false
        var posture: LocationDiagnosticsPosture = .handViewing
        var includesScreenRecording = true
        var includesMicrophone = false
        var isScreenRecordingAvailable = false
        var session: LocationDiagnosticsSessionInfo?
        var startedAt: Date?
        var isStarting = false
        var isFinishing = false
        var screenStatus: ScreenRecordingStatus = .idle
        var isPlacingCheckpoint = false
        var checkpointCenter: IndoorMapCoordinate?
        var checkpointCount = 0
        var jumpMarkerCount = 0
        var lastPosition: IndoorPosition?
        var lastJump: LocationJump?
        var lastQuality: String?
        var lastDistanceToRoute: Double?
        var markerFlashID = 0
        var sessions: [LocationDiagnosticsSessionInfo] = []
        var lastFinishedSession: LocationDiagnosticsSessionInfo?
        var errorMessage: String?

        var isRecording: Bool { session != nil }
    }

    enum DiagnosticsAction: Equatable {
        case panelButtonTapped
        case panelPresentationChanged(Bool)
        case postureChanged(LocationDiagnosticsPosture)
        case screenRecordingToggled(Bool)
        case microphoneToggled(Bool)
        case screenAvailabilityLoaded(Bool)
        case startTapped
        case sessionStarted(LocationDiagnosticsSessionInfo)
        case sessionStartFailed(String)
        case screenStatusChanged(ScreenRecordingStatus)
        case finishTapped
        case sessionFinished(LocationDiagnosticsSessionInfo?)
        case jumpMarkerTapped
        case checkpointModeTapped
        case checkpointCenterChanged(IndoorMapCoordinate)
        case checkpointConfirmed
        case checkpointCancelled
        case destinationCheckpointTapped
        case sessionListAppeared
        case sessionsLoaded([LocationDiagnosticsSessionInfo])
        case deleteSessionTapped(String)
    }

    func reduceDiagnostics(_ state: inout State, _ action: DiagnosticsAction) -> Effect<Action> {
        switch action {
        case .panelButtonTapped:
            state.diagnostics.isPanelPresented = true
            return .run { [diagnosticsClient] send in
                await send(.diagnostics(.screenAvailabilityLoaded(await diagnosticsClient.isScreenRecordingAvailable())))
            }

        case let .panelPresentationChanged(isPresented):
            state.diagnostics.isPanelPresented = isPresented
            return .none

        case let .postureChanged(posture):
            state.diagnostics.posture = posture
            return .none

        case let .screenRecordingToggled(isOn):
            state.diagnostics.includesScreenRecording = isOn
            if !isOn { state.diagnostics.includesMicrophone = false }
            return .none

        case let .microphoneToggled(isOn):
            state.diagnostics.includesMicrophone = isOn && state.diagnostics.includesScreenRecording
            return .none

        case let .screenAvailabilityLoaded(isAvailable):
            state.diagnostics.isScreenRecordingAvailable = isAvailable
            if !isAvailable {
                state.diagnostics.includesScreenRecording = false
                state.diagnostics.includesMicrophone = false
            }
            return .none

        case .startTapped:
            guard !state.diagnostics.isRecording, !state.diagnostics.isStarting else { return .none }
            state.diagnostics.isStarting = true
            state.diagnostics.errorMessage = nil
            let includesScreen = state.diagnostics.includesScreenRecording && state.diagnostics.isScreenRecordingAvailable
            let meta = LocationDiagnosticsSessionMeta(
                startedAt: now, posture: state.diagnostics.posture,
                includesScreenRecording: includesScreen,
                includesMicrophone: includesScreen && state.diagnostics.includesMicrophone,
                routePlanID: state.routePlan.id.uuidString, bookCount: state.routePlan.stops.count,
                startsAtEntrance: state.startsAtEntrance, usesManualOrigin: state.usesManualOrigin,
                guidanceThresholds: [
                    "maximumAccuracyMeters": GuidanceEngine.maximumAccuracyMeters,
                    "matchingRadiusMeters": GuidanceEngine.matchingRadiusMeters,
                    "maximumPositionAgeSeconds": GuidanceEngine.maximumPositionAge,
                    "offRouteRerouteDelaySeconds": Self.offRouteRerouteDelay,
                    "jumpWalkingSpeedLimit": LocationJump.walkingSpeedLimit,
                    "jumpMinimumMeters": LocationJump.minimumJumpMeters
                ])
            return .run { [diagnosticsClient] send in
                do {
                    let info = try await diagnosticsClient.startSession(meta)
                    await send(.diagnostics(.sessionStarted(info)))
                    guard meta.includesScreenRecording else { return }
                    await diagnosticsClient.startScreenRecording(meta.includesMicrophone)
                } catch {
                    await send(.diagnostics(.sessionStartFailed(error.localizedDescription)))
                }
            }

        case let .sessionStarted(info):
            state.diagnostics.isStarting = false
            state.diagnostics.session = info
            state.diagnostics.startedAt = info.meta?.startedAt ?? now
            state.diagnostics.isPanelPresented = false
            state.diagnostics.checkpointCount = 0
            state.diagnostics.jumpMarkerCount = 0
            state.diagnostics.lastPosition = nil
            state.diagnostics.lastJump = nil
            state.diagnostics.screenStatus = info.meta?.includesScreenRecording == true ? .requesting : .idle
            for index in state.plans.indices {
                recordDiagnosticsRoute(state, stopIndex: index, reason: "initial")
            }
            recordDiagnosticsEvent(state, "stop_current", ["stopIndex": "\(state.currentStopIndex)"])
            guard info.meta?.includesScreenRecording == true else { return .none }
            return .run { [diagnosticsClient] send in
                for await status in await diagnosticsClient.screenRecordingStatus() {
                    await send(.diagnostics(.screenStatusChanged(status)))
                }
            }.cancellable(id: CancelID.diagnosticsScreenStatus, cancelInFlight: true)

        case let .sessionStartFailed(message):
            state.diagnostics.isStarting = false
            state.diagnostics.errorMessage = "기록을 시작하지 못했어요. \(message)"
            return .none

        case let .screenStatusChanged(status):
            state.diagnostics.screenStatus = status
            return .none

        case .finishTapped:
            return finishDiagnostics(&state)

        case let .sessionFinished(info):
            state.diagnostics.isFinishing = false
            state.diagnostics.lastFinishedSession = info
            if let info { state.diagnostics.sessions.removeAll { $0.id == info.id } }
            if let info { state.diagnostics.sessions.insert(info, at: 0) }
            return .none

        case .jumpMarkerTapped:
            guard state.diagnostics.isRecording else { return .none }
            state.diagnostics.jumpMarkerCount += 1
            state.diagnostics.markerFlashID += 1
            let position = state.rawPosition
            diagnosticsClient.record(.marker(.init(
                at: now, kind: .jump, latitude: position?.coordinate.latitude,
                longitude: position?.coordinate.longitude, floorOrdinal: position?.floorOrdinal,
                label: "jump #\(state.diagnostics.jumpMarkerCount)")))
            return .none

        case .checkpointModeTapped:
            guard state.diagnostics.isRecording else { return .none }
            state.diagnostics.isPanelPresented = false
            state.diagnostics.isPlacingCheckpoint = true
            state.diagnostics.checkpointCenter = nil
            state.followsNavigationCamera = false
            return .none

        case let .checkpointCenterChanged(coordinate):
            guard state.diagnostics.isPlacingCheckpoint else { return .none }
            state.diagnostics.checkpointCenter = coordinate
            return .none

        case .checkpointConfirmed:
            guard state.diagnostics.isRecording, state.diagnostics.isPlacingCheckpoint,
                  let center = state.diagnostics.checkpointCenter else { return .none }
            state.diagnostics.checkpointCount += 1
            state.diagnostics.markerFlashID += 1
            diagnosticsClient.record(.marker(.init(
                at: now, kind: .checkpoint, latitude: center.latitude, longitude: center.longitude,
                floorOrdinal: state.currentFloor?.ordinal, label: "checkpoint #\(state.diagnostics.checkpointCount)")))
            return endCheckpointPlacement(&state)

        case .checkpointCancelled:
            return endCheckpointPlacement(&state)

        case .destinationCheckpointTapped:
            guard state.diagnostics.isRecording, let plan = state.currentPlan else { return .none }
            state.diagnostics.isPanelPresented = false
            state.diagnostics.checkpointCount += 1
            state.diagnostics.markerFlashID += 1
            diagnosticsClient.record(.marker(.init(
                at: now, kind: .destination, latitude: plan.destination.coordinate.latitude,
                longitude: plan.destination.coordinate.longitude, floorOrdinal: plan.destination.level,
                label: "destination stop \(state.currentStopIndex)")))
            return .none

        case .sessionListAppeared:
            return .run { [diagnosticsClient] send in
                await send(.diagnostics(.sessionsLoaded(await diagnosticsClient.sessions())))
            }

        case let .sessionsLoaded(sessions):
            state.diagnostics.sessions = sessions
            return .none

        case let .deleteSessionTapped(id):
            guard state.diagnostics.session?.id != id else { return .none }
            state.diagnostics.sessions.removeAll { $0.id == id }
            return .run { [diagnosticsClient] _ in await diagnosticsClient.deleteSession(id) }
        }
    }

    func finishDiagnostics(_ state: inout State) -> Effect<Action> {
        guard state.diagnostics.isRecording, !state.diagnostics.isFinishing else { return .none }
        state.diagnostics.isFinishing = true
        state.diagnostics.session = nil
        state.diagnostics.startedAt = nil
        state.diagnostics.isPlacingCheckpoint = false
        return .merge(
            .cancel(id: CancelID.diagnosticsScreenStatus),
            .run { [diagnosticsClient] send in
                await send(.diagnostics(.sessionFinished(await diagnosticsClient.finishSession())))
            }
        )
    }

    private func endCheckpointPlacement(_ state: inout State) -> Effect<Action> {
        state.diagnostics.isPlacingCheckpoint = false
        state.diagnostics.checkpointCenter = nil
        state.followsNavigationCamera = true
        if !updateCamera(&state, force: true) { fitCurrentRoute(&state) }
        return .none
    }

    /// 위치 1건을 처리한 결과와 화면에 그린 값을 남긴다.
    func recordGuidanceDiagnostics(_ state: inout State, position: IndoorPosition, quality: String) {
        guard state.diagnostics.isRecording else { return }
        if let jump = LocationJump(from: state.diagnostics.lastPosition, to: position) {
            state.diagnostics.lastJump = jump
        }
        state.diagnostics.lastPosition = position
        state.diagnostics.lastQuality = quality
        let progress = state.displayedProgress
        let effective = state.latestPosition?.coordinate ?? position.coordinate
        let distanceToRoute = state.progress.map { RoutingGeometry.distanceMeters(from: effective, to: $0.coordinate) }
        state.diagnostics.lastDistanceToRoute = distanceToRoute
        let displayed = state.mapPosition?.coordinate
        diagnosticsClient.record(.guidance(.init(
            at: now, positionTimestamp: position.timestamp, stopIndex: state.currentStopIndex, quality: quality,
            floorOrdinal: state.latestPosition?.floorOrdinal ?? position.floorOrdinal,
            displayedLatitude: displayed?.latitude, displayedLongitude: displayed?.longitude,
            matchedLatitude: state.progress?.coordinate.latitude, matchedLongitude: state.progress?.coordinate.longitude,
            distanceToRoute: distanceToRoute, distanceAlongRoute: state.progress?.distanceAlongRoute,
            remainingMeters: progress?.remainingMeters, stepIndex: progress?.stepIndex,
            maneuver: progress.map { Self.maneuverName($0.maneuver) },
            instruction: state.nextBookRouteError ?? state.statusMessage ?? state.instructionText,
            cameraRequestID: state.cameraRequest.id)))
    }

    func recordDiagnosticsEvent(_ state: State, _ name: String, _ detail: [String: String] = [:]) {
        guard state.diagnostics.isRecording else { return }
        diagnosticsClient.record(.event(.init(at: now, name: name, detail: detail)))
    }

    func recordDiagnosticsRoute(_ state: State, stopIndex: Int, reason: String) {
        guard state.diagnostics.isRecording, state.plans.indices.contains(stopIndex),
              let plan = state.plans[stopIndex] else { return }
        var segments: [LocationDiagnosticsRecord.RouteSnapshot.Segment] = []
        for step in plan.steps where !step.changesFloor {
            let coordinates = step.coordinates.map { [$0.latitude, $0.longitude] }
            if var last = segments.last, last.floorOrdinal == step.from.level {
                last.coordinates += last.coordinates.last == coordinates.first ? Array(coordinates.dropFirst()) : coordinates
                segments[segments.count - 1] = last
            } else {
                segments.append(.init(floorOrdinal: step.from.level, coordinates: coordinates))
            }
        }
        diagnosticsClient.record(.route(.init(
            at: now, stopIndex: stopIndex, reason: reason, segments: segments,
            destinationLatitude: plan.destination.coordinate.latitude,
            destinationLongitude: plan.destination.coordinate.longitude,
            destinationFloorOrdinal: plan.destination.level)))
    }

    static func maneuverName(_ maneuver: RouteManeuver) -> String {
        switch maneuver {
        case .straight: "straight"
        case .left: "left"
        case .right: "right"
        case .turnAround: "turn_around"
        case .nearDestination: "near_destination"
        case let .changeFloor(category, _): "change_floor_\(category.rawValue)"
        }
    }
}
