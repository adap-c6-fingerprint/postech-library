import CoreLocation
import Foundation

/// 권한 콜백의 스냅샷을 보관하고, 기기 전체 서비스 상태 조회만 별도 executor에서 수행한다.
@MainActor
final class IndoorLocationAuthorizationMonitor {
    private(set) var authorization: IndoorLocationAuthorization = .notDetermined
    private let servicesEnabled: @Sendable () async -> Bool
    private let onChange: @MainActor (IndoorLocationAuthorization) -> Void
    private var servicesTask: Task<Void, Never>?
    private var revision = 0

    init(
        servicesEnabled: @escaping @Sendable () async -> Bool = { await IndoorLocationServices.queryEnabled() },
        onChange: @escaping @MainActor (IndoorLocationAuthorization) -> Void
    ) {
        self.servicesEnabled = servicesEnabled
        self.onChange = onChange
    }

    deinit { servicesTask?.cancel() }

    @discardableResult
    func update(status: CLAuthorizationStatus, precise: Bool) -> Task<Void, Never>? {
        servicesTask?.cancel()
        servicesTask = nil
        revision += 1
        switch status {
        case .notDetermined:
            setAuthorization(.notDetermined)
        case .restricted:
            setAuthorization(.restricted)
        case .authorizedWhenInUse, .authorizedAlways:
            setAuthorization(.authorized(precise: precise))
        case .denied:
            // 권한 철회 시 느린 시스템 조회를 기다리지 않고 위치 업데이트를 중지한다.
            setAuthorization(.denied)
            let currentRevision = revision
            let check = servicesEnabled
            servicesTask = Task { [weak self] in
                guard !Task.isCancelled else { return }
                let enabled = await check()
                guard !Task.isCancelled, let self, self.revision == currentRevision else { return }
                self.setAuthorization(enabled ? .denied : .servicesDisabled)
            }
        @unknown default:
            setAuthorization(.restricted)
        }
        return servicesTask
    }

    private func setAuthorization(_ value: IndoorLocationAuthorization) {
        guard authorization != value else { return }
        authorization = value
        onChange(value)
    }
}

nonisolated enum IndoorLocationServices {
    /// @concurrent는 호출자가 MainActor여도 동기 시스템 조회를 그 executor 밖에서 실행한다.
    @concurrent
    static func queryEnabled(
        _ query: @Sendable () -> Bool = { CLLocationManager.locationServicesEnabled() }
    ) async -> Bool {
        query()
    }
}
