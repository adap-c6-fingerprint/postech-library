//
//  RoutePlanningInput.swift
//  fingerprint-library
//
//  Created by Youngmin Cho on 10/31/26.
//

import Foundation

/// 파일 검증과 서가의 도착 노드 연결이 끝난 입력
nonisolated struct RoutePlanningInput: Sendable {
    // 최종 Session에 담아서 지도, 안내 화면에 전달
    let map: IndoorMap
    let shelfLabels: [IndoorShelfLabel]

    // 경로 계산에 필요한 통로 그래프와 서가별 도착 노드
    let navigation: IndoorNavigationData

    // 앱에서 확인한 실제 계산용 출발 위치. 출발점은 서가에 한정되지 않는다.
    let start: IndoorPosition

    // 방문할 책과 서가 목록
    let stops: [RouteCandidateStop]
}
