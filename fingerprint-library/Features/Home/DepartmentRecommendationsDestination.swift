//
//  DepartmentRecommendationsDestination.swift
//  fingerprint-library
//

import ComposableArchitecture

@Reducer
struct DepartmentRecommendationsDestination {
    @ObservableState
    struct State: Equatable {}

    enum Action {}

    var body: some Reducer<State, Action> {
        EmptyReducer()
    }
}
