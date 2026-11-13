//
//  UserProfile.swift
//  fingerprint-library
//
//  Created by 이시온 on 10/27/26.
//
//  사용자 프로필: 온보딩에서 고른 소속·학과와 관심 분야.
//  앱 전체에 이 값이 하나만 있다(single source of truth). 저장 위치는 SharedState/UserProfileSharedKeys.swift의
//  `@Shared(.userProfile)`이며, 온보딩·마이페이지·홈·추천이 모두 그 하나를 함께 읽고 쓴다.
//

import Foundation

nonisolated struct UserProfile: Codable, Equatable, Sendable {
    let affiliationKey: [String]
    let departmentName: String
    let interests: [String]

    init(affiliationKey: [String], departmentName: String, interests: [String]) throws {
        self.affiliationKey = try Self.validatedAffiliationKey(affiliationKey)
        self.departmentName = try Self.validatedDepartmentName(departmentName)
        self.interests = try Self.validatedInterests(interests)
    }

    func updatingAffiliation(key: [String], departmentName: String) throws -> UserProfile {
        try UserProfile(affiliationKey: key, departmentName: departmentName, interests: interests)
    }

    func updatingInterests(_ newInterests: [String]) throws -> UserProfile {
        try UserProfile(affiliationKey: affiliationKey, departmentName: departmentName, interests: newInterests)
    }

    var promptText: String {
        "학과: \(departmentName)\n관심사: \(interests.joined(separator: ", "))"
    }

    private static func validatedAffiliationKey(_ key: [String]) throws -> [String] {
        let trimmed = key.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard trimmed.count == 3, !trimmed.contains(where: \.isEmpty) else {
            throw UserProfileError.invalidAffiliation
        }
        return trimmed
    }

    private static func validatedDepartmentName(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw UserProfileError.emptyDepartmentName }
        return trimmed
    }

    private static func validatedInterests(_ values: [String]) throws -> [String] {
        var unique: [String] = []
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw UserProfileError.emptyInterest }
            if !unique.contains(trimmed) { unique.append(trimmed) }
        }
        return unique
    }
}

nonisolated enum UserProfileError: Error, Equatable {
    case emptyDepartmentName
    case emptyInterest
    case invalidAffiliation
}
