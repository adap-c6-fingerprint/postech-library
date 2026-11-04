import ComposableArchitecture
import SwiftUI

/// 어느 화면에서 길안내를 열어도 앱 루트가 수신 중인 동일한 위치를 읽는다.
private struct IndoorRouteMapStoreKey: EnvironmentKey {
    static var defaultValue: StoreOf<IndoorMapFeature>? { nil }
}

extension EnvironmentValues {
    var indoorRouteMapStore: StoreOf<IndoorMapFeature>? {
        get { self[IndoorRouteMapStoreKey.self] }
        set { self[IndoorRouteMapStoreKey.self] = newValue }
    }
}
