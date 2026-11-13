//
//  RoutePlanningInput.swift
//  fingerprint-library
//
//  Created by Youngmin Cho on 10/31/26.
//

import Foundation

nonisolated struct RoutePlanningInput: Sendable {
    let map: IndoorMap
    let shelfLabels: [IndoorShelfLabel]

    let navigation: IndoorNavigationData

    let start: IndoorPosition

    let stops: [RouteCandidateStop]
}
