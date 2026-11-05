import Foundation

nonisolated enum BookAPIProvider: String, CaseIterable, Sendable {
    case primo, yes24, data4Library

    var credentialName: String {
        switch self {
        case .primo: "PRIMO_API_KEY"
        case .yes24: "YES24_API_KEY"
        case .data4Library: "DATA4LIBRARY_API_KEY"
        }
    }
}

/// API 경로는 개인정보 수집 동의와 별도로 저장한다.
nonisolated struct APIRoutingSettings: Equatable, Sendable {
    var primo = true
    var yes24 = true
    var data4Library = true

    subscript(provider: BookAPIProvider) -> Bool {
        get {
            switch provider {
            case .primo: primo
            case .yes24: yes24
            case .data4Library: data4Library
            }
        }
        set {
            switch provider {
            case .primo: primo = newValue
            case .yes24: yes24 = newValue
            case .data4Library: data4Library = newValue
            }
        }
    }

    static func load(from defaults: UserDefaults = .standard) -> Self {
        var settings = Self()
        for provider in BookAPIProvider.allCases {
            settings[provider] = defaults.object(forKey: "apiRouting.\(provider.rawValue).usesRelay") as? Bool ?? true
        }
        return settings
    }

    func save(to defaults: UserDefaults = .standard) {
        for provider in BookAPIProvider.allCases {
            defaults.set(self[provider], forKey: "apiRouting.\(provider.rawValue).usesRelay")
        }
    }
}
