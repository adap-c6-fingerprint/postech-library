//
//  UserProfile.swift
//  fingerprint-library
//
//  Created by 이시온 on 10/27/26.
//
//  사용자 프로필: 온보딩에서 고른 소속·학과와 관심 분야.
//  앱 전체에 이 값이 하나만 있다(single source of truth). 저장 위치는 Clients/User/UserProfileStorage.swift의
//  `@Shared(.userProfile)`이며, 온보딩·마이페이지·홈·추천이 모두 그 하나를 함께 읽고 쓴다.
//

import Foundation

nonisolated struct UserProfile: Codable, Equatable, Sendable {
    let affiliationKey: [String]
    // 소속 경로 3단계. 예: ["POSTECH 학부", "학과 및 학부", "수학과"]
    // 이름만으로는 학부·대학원의 같은 학과가 섞이므로 세 값을 함께 저장한다.
    let departmentName: String
    // 화면에 보여줄 최종 소속 이름. 예: "수학과" (홈 "'수학과'에서 많이 빌린" 제목)
    let interests: [String]
    // 고른 순서대로의 관심 분야(선호 분류) 이름. 예: ["수학", "역사"]

    init(affiliationKey: [String], departmentName: String, interests: [String]) throws {
    // 값이 규칙에 어긋나면 만들지 않고 오류를 던진다(throws).
        self.affiliationKey = try Self.validatedAffiliationKey(affiliationKey)
        self.departmentName = try Self.validatedDepartmentName(departmentName)
        self.interests = try Self.validatedInterests(interests)
    }

    // MARK: - 바꾼 사본 만들기

    func updatingAffiliation(key: [String], departmentName: String) throws -> UserProfile {
    // 마이페이지에서 소속·학과만 바꿀 때 쓴다. 관심 분야는 그대로 둔다.
        try UserProfile(affiliationKey: key, departmentName: departmentName, interests: interests)
    }

    func updatingInterests(_ newInterests: [String]) throws -> UserProfile {
    // 마이페이지에서 관심 분야만 바꿀 때 쓴다. 소속·학과는 그대로 둔다.
        try UserProfile(affiliationKey: affiliationKey, departmentName: departmentName, interests: newInterests)
    }

    var promptText: String {
    // Foundation Model 프롬프트에 그대로 넣을 수 있는 문장.
        "학과: \(departmentName)\n관심사: \(interests.joined(separator: ", "))"
        // 예: "학과: 반도체공학과\n관심사: A, P, Q"
    }

    // MARK: - 검사

    private static func validatedAffiliationKey(_ key: [String]) throws -> [String] {
    // 소속 경로는 [상위 소속, 그룹, 최종 소속] 세 값이 모두 있어야 한다.
        let trimmed = key.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard trimmed.count == 3, !trimmed.contains(where: \.isEmpty) else {
            throw UserProfileError.invalidAffiliation
        }
        return trimmed
    }

    private static func validatedDepartmentName(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        // 앞뒤 공백·줄바꿈을 지운다. 예: " 반도체공학과 " → "반도체공학과"
        guard !trimmed.isEmpty else { throw UserProfileError.emptyDepartmentName }
        return trimmed
    }

    private static func validatedInterests(_ values: [String]) throws -> [String] {
        var unique: [String] = []
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw UserProfileError.emptyInterest }
            if !unique.contains(trimmed) { unique.append(trimmed) }
            // 처음 나온 값만 담는다. ["A", "A"]처럼 같은 값이 두 번 저장되지 않게 한다.
        }
        return unique
        // 입력 순서는 그대로 유지된다.
    }
}

nonisolated enum UserProfileError: Error, Equatable {
// 프로필 규칙을 어겼을 때의 오류 종류.
    case emptyDepartmentName
    // 학과가 비어 있음.
    case emptyInterest
    // 관심사 중 빈 값이 있음.
    case invalidAffiliation
    // 소속 경로가 세 단계로 이루어지지 않음.
}
