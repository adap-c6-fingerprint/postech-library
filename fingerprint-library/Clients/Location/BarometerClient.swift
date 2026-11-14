import ComposableArchitecture
import Foundation

nonisolated struct BarometerSample: Equatable, Sendable {
    let kilopascals: Double
    let timestamp: Date
}

nonisolated struct BarometerClient: Sendable {
    var samples: @Sendable () async -> AsyncStream<BarometerSample>
}

extension BarometerClient: DependencyKey {
    static let liveValue = Self(samples: { await LiveBarometerProvider.shared.samples() })
    static let testValue = Self(samples: { AsyncStream { $0.finish() } })
}

nonisolated extension DependencyValues {
    var barometerClient: BarometerClient {
        get { self[BarometerClient.self] }
        set { self[BarometerClient.self] = newValue }
    }
}
