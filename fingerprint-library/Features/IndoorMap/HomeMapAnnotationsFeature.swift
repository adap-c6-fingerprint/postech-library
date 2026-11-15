import ComposableArchitecture

@Reducer
struct HomeMapAnnotationsFeature {
    @ObservableState
    struct State: Equatable {
        var showsAmenities = false
        var favoriteKeys: Set<[String?]> = []
        var holdings: [[String?]: [BookHolding]] = [:]
    }

    enum Action: Equatable {
        case task
        case amenitiesTapped
        case favoritesChanged(Set<[String?]>)
        case localLocationsChanged
        case disappeared
    }

    @Dependency(\.bookLocationCacheClient) var locations
    @Dependency(\.analyticsClient) private var analytics
    nonisolated private enum CancelID { case updates }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .task:
                return .run { [locations] send in
                    await locations.prepare()
                    for await _ in locations.updates() {
                        guard !Task.isCancelled else { return }
                        await send(.localLocationsChanged)
                    }
                }.cancellable(id: CancelID.updates, cancelInFlight: true)
            case .amenitiesTapped:
                state.showsAmenities.toggle()
                analytics.record(.button(.amenityToggle, on: .map,
                                         [.action: .text(state.showsAmenities ? "on" : "off")]))
                // 편의시설 버튼은 지도 탭에만 있다. 토글한 뒤의 상태(on, off)를 보낸다
                return .none
            case .favoritesChanged(let keys):
                state.favoriteKeys = keys
                state.holdings = locations.load(keys)
                return .none
            case .localLocationsChanged:
                state.holdings = locations.load(state.favoriteKeys)
                return .none
            case .disappeared:
                return .cancel(id: CancelID.updates)
            }
        }
    }
}

