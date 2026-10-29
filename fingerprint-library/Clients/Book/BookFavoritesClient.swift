import Foundation
import ComposableArchitecture

nonisolated struct BookFavoritesClient: Sendable {
    var load: @Sendable () -> Set<[String?]>
    var save: @Sendable (Set<[String?]>) -> Void

    static func userDefaults(suiteName: String? = nil) -> Self {
        Self(
            load: {
                let defaults = suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
                guard let data = defaults.data(forKey: BookStorageKey.favoriteRecordKeys) else { return [] }
                return (try? JSONDecoder().decode(Set<[String?]>.self, from: data)) ?? []
            },
            save: { keys in
                guard let data = try? JSONEncoder().encode(keys) else { return }
                let defaults = suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
                defaults.set(data, forKey: BookStorageKey.favoriteRecordKeys)
            }
        )
    }

    /// 다른 화면이 추가한 찜도 보존하도록 저장소의 최신 목록을 기준으로 변경한다.
    func toggle(_ book: Book) -> Set<[String?]> {
        var keys = load()
        let key = book.recordKey
        if keys.contains(key) { keys.remove(key) }
        else { keys.insert(key) }
        save(keys)
        return keys
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
