import ComposableArchitecture
import Foundation

nonisolated struct IndoorLocationClient: Sendable {
    var events: @Sendable () async -> AsyncStream<IndoorLocationEvent>
    var requestPermission: @Sendable () async -> Void
}

extension IndoorLocationClient: DependencyKey {
    static let liveValue = Self(
        events: {
            #if DEBUG
            if usesSimulation { return await IndoorSimulationDeviceLocationProvider.events() }
            #endif
            return await LiveIndoorLocationProvider.shared.events()
        },
        requestPermission: {
            await LiveIndoorLocationProvider.shared.requestPermission()
        }
    )
    static let testValue = Self(events: { AsyncStream { $0.finish() } }, requestPermission: {})
}

nonisolated extension DependencyValues {
    var indoorLocationClient: IndoorLocationClient {
        get { self[IndoorLocationClient.self] }
        set { self[IndoorLocationClient.self] = newValue }
    }
}

#if DEBUG
nonisolated extension IndoorLocationClient {
    static var usesSimulation: Bool {
        IndoorSimulationSettings.load().usesSimulation(environment: ProcessInfo.processInfo.environment)
    }
}
#endif
