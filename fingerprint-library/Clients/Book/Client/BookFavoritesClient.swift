import Foundation
import ComposableArchitecture

nonisolated struct BookFavoritesClient: Sendable {
    var load: @Sendable () -> Set<[String?]>
    var save: @Sendable (Set<[String?]>) -> Void

    private static let storageKey = "favoriteBookRecordKeys"

    static func userDefaults(suiteName: String? = nil) -> Self {
        Self(
            load: {
                let defaults = suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
                guard let data = defaults.data(forKey: storageKey) else { return [] }
                return (try? JSONDecoder().decode(Set<[String?]>.self, from: data)) ?? []
            },
            save: { keys in
                guard let data = try? JSONEncoder().encode(keys) else { return }
                let defaults = suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
                defaults.set(data, forKey: storageKey)
            }
        )
    }
}

extension BookFavoritesClient: DependencyKey {
    static let liveValue = Self.userDefaults()
    static let testValue = Self(load: { [] }, save: { _ in })
}

extension DependencyValues {
    var bookFavoritesClient: BookFavoritesClient {
        get { self[BookFavoritesClient.self] }
        set { self[BookFavoritesClient.self] = newValue }
    }
}
