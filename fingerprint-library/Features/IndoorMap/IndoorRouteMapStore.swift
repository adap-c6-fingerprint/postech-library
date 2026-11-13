import ComposableArchitecture
import SwiftUI

private struct IndoorRouteMapStoreKey: EnvironmentKey {
    static var defaultValue: StoreOf<IndoorMapFeature>? { nil }
}

extension EnvironmentValues {
    var indoorRouteMapStore: StoreOf<IndoorMapFeature>? {
        get { self[IndoorRouteMapStoreKey.self] }
        set { self[IndoorRouteMapStoreKey.self] = newValue }
    }
}
