//
//  PostechStatus.swift
//  fingerprint-library
//
//  Created by 이시온 on 10/28/26.
//

import Foundation

enum PostechStatus: String, CaseIterable, Codable, Identifiable, Sendable {
    case undergraduate
    case graduate
    case staff
    case appleDeveloperAcademy

    var id: String { rawValue }

    var koreanName: String {
        switch self {
        case .undergraduate: "POSTECH 학부"
        case .graduate: "POSTECH 대학원"
        case .staff: "POSTECH 교직원"
        case .appleDeveloperAcademy: "Apple Developer Academy"
        }
    }

    var departments: [PostechDepartment] {
        switch self {
        case .undergraduate:
            PostechDepartment.Undergraduate.allCases.map(PostechDepartment.undergraduate)
        case .graduate:
            PostechDepartment.Graduate.allCases.map(PostechDepartment.graduate)
        case .staff, .appleDeveloperAcademy:
            []
        }
    }

    var requiresDepartment: Bool {
        !departments.isEmpty
    }
}
