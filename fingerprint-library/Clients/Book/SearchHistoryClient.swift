import Foundation
import ComposableArchitecture

nonisolated struct SearchHistoryClient: Sendable {
    var load: @Sendable () -> [String]
    var save: @Sendable ([String]) -> Void

    private static let storageKey = "recentSearchQueries"

    // 테스트에서는 별도 suite를 사용해 앱의 실제 검색 기록과 분리한다.
    static func userDefaults(suiteName: String? = nil) -> Self {
        Self(
            load: {
                let defaults = suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
                return defaults.stringArray(forKey: storageKey) ?? []
            },
            save: { queries in
                let defaults = suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
                defaults.set(queries, forKey: storageKey)
            }
        )
    }
}

extension SearchHistoryClient: DependencyKey {
    static let liveValue = Self.userDefaults()

    static let testValue = Self(
        load: { [] },
        save: { _ in }
    )
}

extension DependencyValues {
    var searchHistoryClient: SearchHistoryClient {
        get { self[SearchHistoryClient.self] }
        set { self[SearchHistoryClient.self] = newValue }
    }
}
