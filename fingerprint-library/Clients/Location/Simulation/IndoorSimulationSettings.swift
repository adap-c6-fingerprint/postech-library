#if DEBUG
import Foundation

/// Debug 연결 화면에서 선택한 설정. Release에는 저장·선택 코드를 포함하지 않는다.
nonisolated struct IndoorSimulationSettings: Codable, Equatable, Sendable {
    enum Source: String, Codable, Sendable { case automatic, simulation, live }
    var source: Source = .automatic
    /// nil은 실행 환경을 따르고, 빈 문자열은 호스트 강제 지정을 해제한다.
    var host: String?
    var port: UInt16?
    private static let storageKey = "PoBook.indoorSimulationSettings"

    static func load(from defaults: UserDefaults = .standard) -> Self {
        guard let data = defaults.data(forKey: storageKey),
              let value = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        return value
    }

    func save(to defaults: UserDefaults = .standard) throws {
        defaults.set(try JSONEncoder().encode(self), forKey: Self.storageKey)
    }

    static func reset(in defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: storageKey)
    }

    func usesSimulation(environment: [String: String]) -> Bool {
        switch source {
        case .automatic:
            IndoorSimulationConfiguration.usesSimulation(environment: environment)
        case .simulation: true
        case .live: false
        }
    }

    func connection(environment: [String: String], isSimulator: Bool) throws -> IndoorSimulationConfiguration {
        var resolved = environment
        if let host {
            let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                resolved.removeValue(forKey: "INDOOR_SIMULATOR_HOST")
            } else {
                resolved["INDOOR_SIMULATOR_HOST"] = trimmed
            }
        }
        if let port { resolved["INDOOR_SIMULATOR_PORT"] = String(port) }
        return try IndoorSimulationConfiguration.connection(environment: resolved, isSimulator: isSimulator)
    }
}
#endif
