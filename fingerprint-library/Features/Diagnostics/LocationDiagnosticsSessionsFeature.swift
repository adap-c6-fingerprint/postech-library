import ComposableArchitecture
import Foundation

/// 저장된 위치 측정 기록 목록과 삭제(실험 브랜치 전용).
/// 마이페이지에서 검색창 `/test` 측정 모드가 켜져 있을 때만 들어올 수 있다.
@Reducer
struct LocationDiagnosticsSessionsFeature {
    @ObservableState
    struct State: Equatable {
        var sessions: [LocationDiagnosticsSessionInfo] = []
        var isLoading = false
    }

    enum Action: Equatable {
        case task
        case sessionsLoaded([LocationDiagnosticsSessionInfo])
        case deleteTapped(String)
    }

    @Dependency(\.locationDiagnosticsClient) var diagnosticsClient

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .task:
                state.isLoading = true
                return .run { [diagnosticsClient] send in
                    await send(.sessionsLoaded(await diagnosticsClient.sessions()))
                }

            case let .sessionsLoaded(sessions):
                state.isLoading = false
                state.sessions = sessions
                return .none

            case let .deleteTapped(id):
                state.sessions.removeAll { $0.id == id }
                return .run { [diagnosticsClient] _ in await diagnosticsClient.deleteSession(id) }
            }
        }
    }
}
