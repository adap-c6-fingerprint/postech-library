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
        var isSelectingForGuidance = false
        // 길안내할 책을 고른 순서대로 보관한다.
        var selectedIDs: [Book.ID] = []

        var sections: [BookBasketSection] {
            BookBasketSection.grouped(items, calendar: .current)
        }

        var selectedCount: Int { selectedIDs.count }
    }

    enum Action {
        case task
        case selectButtonTapped
        case doneButtonTapped
        case selectionToggled(Book.ID)
        case startGuidanceButtonTapped
    }

    @Dependency(\.bookBasketClient)
    var bookBasketClient: BookBasketClient

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .task:
                state.items = bookBasketClient.load()
                return .none

            case .selectButtonTapped:
                state.isSelectingForGuidance = true
                return .none

            case .doneButtonTapped:
                state.isSelectingForGuidance = false
                state.selectedIDs = []
                return .none

            case let .selectionToggled(id):
                guard state.isSelectingForGuidance,
                      state.items.contains(where: { $0.id == id })
                else { return .none }
                if let index = state.selectedIDs.firstIndex(of: id) {
                    state.selectedIDs.remove(at: index)
                } else {
                    state.selectedIDs.append(id)
                }
                return .none

            case .startGuidanceButtonTapped:
                return .none
            }
        }
    }
}
