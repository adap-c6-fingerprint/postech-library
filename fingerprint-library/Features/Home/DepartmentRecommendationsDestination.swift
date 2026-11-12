//
//  DepartmentRecommendationsDestination.swift
//  fingerprint-library
//

import ComposableArchitecture

/// 학과에서 많이 빌린 도서 목록 화면을 App의 이동 스택에 쌓기 위한 목적지.
/// 목록 데이터와 조회는 홈 상태를 그대로 쓰므로 자체 상태와 액션이 없다.
@Reducer
struct DepartmentRecommendationsDestination {
    @ObservableState
    struct State: Equatable {}

    enum Action {}

    var body: some Reducer<State, Action> {
        EmptyReducer()
    }
}
