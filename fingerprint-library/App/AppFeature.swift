//
//  AppFeature.swift
//  2026-C6-M06-Fingerprint-library
//
//  Created by Youngmin Cho on 10/15/26.
//

import ComposableArchitecture

@Reducer
struct AppFeature {
    @ObservableState
    struct State: Equatable {
        var indoorMap = IndoorMapFeature.State()
    }

    enum Action {
        case indoorMap(IndoorMapFeature.Action)
    }

    var body: some Reducer<State, Action> {
        Scope(state: \.indoorMap, action: \.indoorMap) { IndoorMapFeature() }
    }
}
