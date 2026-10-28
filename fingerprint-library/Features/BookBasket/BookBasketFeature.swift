//
//  BookBasketFeature.swift
//  fingerprint-library
//

import Foundation
import ComposableArchitecture

@Reducer
struct BookBasketFeature {
    @ObservableState
    struct State: Equatable {
        var items: [BookBasketItem] = []
    }

    enum Action {
        case task
    }

    @Dependency(\.bookBasketClient)
    var bookBasketClient: BookBasketClient

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .task:
                state.items = bookBasketClient.load()
                return .none
            }
        }
    }
}
