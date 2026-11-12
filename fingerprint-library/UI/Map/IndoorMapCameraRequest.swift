//
//  IndoorMapCameraRequest.swift
//  fingerprint-library
//

import Foundation

/// TCA에서 MapKit으로 전달하는 값 기반 카메라 이동 요청.
/// View는 요청 ID를 기억해 일반 상태 갱신이 사용자의 지도 이동을 덮어쓰지 않게 한다.
nonisolated struct IndoorMapCameraRequest: Equatable, Sendable {
    enum Target: Equatable, Sendable {
        /// 최초 표시 층의 중심을 기준으로 도면을 확대한다. 일반 층 전환에서는 요청하지 않는다.
        case initialFloor(UUID)
        /// 지정 층의 도형 전체를 표시 영역에 맞춘다.
        case floor(UUID)
        /// 현재 줌을 유지한 채 해당 좌표를 가려지지 않는 영역의 중심으로 이동한다.
        /// `revealsShelfNumbers`면 북쪽이 위로 오게 하고, 서가 번호 묶음이 풀리는 배율로 확대한다.
        case position(IndoorMapCoordinate, revealsShelfNumbers: Bool)
        /// 같은 층의 서가 후보들을 함께 볼 수 있도록 도형 전체에 맞춘다.
        case features([IndoorMapElement.ID])
        /// 표시 층의 경로 전체와 출발·도착 서가 도형을 함께 맞춘다.
        case route(IndoorRoute, featureIDs: [IndoorMapElement.ID])
        /// 안내 중 현재 위치와 다음 구간에 맞춰 포커스와 확대 범위를 갱신한다.
        case navigation(BookNavigationCameraFocus)
    }
    let id: Int
    let target: Target
}

/// 길안내 카메라에 함께 보여 줄 현재 위치와 다음 안내 구간.
nonisolated struct BookNavigationCameraFocus: Equatable, Sendable {
    let floorID: UUID
    let coordinates: [IndoorMapCoordinate]
    let minimumSpanMeters: Double
}
