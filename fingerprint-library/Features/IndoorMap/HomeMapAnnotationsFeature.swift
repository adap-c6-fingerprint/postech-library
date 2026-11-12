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
