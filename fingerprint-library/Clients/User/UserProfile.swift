//
//  UserProfile.swift
//  fingerprint-library
//
//  Created by 이시온 on 10/27/26.
//

import Foundation
import SwiftData
// SwiftData: 기기 안 데이터베이스에 객체를 영구 저장하는 Apple 프레임워크.

@Model
// 이 클래스를 SwiftData 저장 대상으로 만든다. 앱을 꺼도 값이 남는다.
// @Model은 class에만 붙일 수 있다.
final class UserProfile {
    static let placeholderDepartmentName = "반도체공학과"
    // 온보딩 화면이 완성되기 전까지 쓰는 임시 학과.
    static let placeholderInterests = ["A", "P", "Q"]
    // 온보딩 화면이 완성되기 전까지 쓰는 임시 관심사.

    private(set) var departmentName: String
    // 학과 이름. 예: "반도체공학과"
    // private(set): 바깥에서는 읽기만 되고, 바꾸려면 아래 update 함수를 거쳐야 한다.
    private(set) var interests: [String]
    // 관심사 목록. 예: ["A", "P", "Q"]
    // 같은 이유로 private(set). 빈 값이나 중복이 검사 없이 들어가는 실수를 막는다.

    init(departmentName: String, interests: [String]) throws {
    // 새 프로필을 만든다. 온보딩에서 입력이 끝났을 때 부른다.
    // 값이 규칙에 어긋나면 만들지 않고 오류를 던진다(throws).
        let department = try Self.validatedDepartmentName(departmentName)
        // 학과 이름을 먼저 검사·정리한다.
        let validInterests = try Self.validatedInterests(interests)
        // 관심사 목록을 먼저 검사·정리한다.
        self.departmentName = department
        // 검사를 통과한 값만 저장한다.
        self.interests = validInterests
    }

    // MARK: - 설정 화면에서 수정

    func updateDepartmentName(_ name: String) throws {
    // 설정 화면에서 학과를 바꿀 때 부른다.
        departmentName = try Self.validatedDepartmentName(name)
        // 검사를 통과해야만 바뀐다. 실패하면 기존 값이 그대로 남는다.
    }

    func updateInterests(_ newInterests: [String]) throws {
    // 설정 화면에서 관심사를 바꿀 때 부른다.
        interests = try Self.validatedInterests(newInterests)
        // 검사를 통과해야만 바뀐다. 실패하면 기존 값이 그대로 남는다.
    }

    // MARK: - Foundation Model 전달용

    var snapshot: UserProfileSnapshot {
    // 현재 값을 복사한 "사진"을 만든다.
    // @Model 객체는 다른 스레드로 넘길 수 없어서, Foundation Model처럼
    // 비동기로 도는 코드에는 이 복사본을 넘긴다.
        UserProfileSnapshot(departmentName: departmentName, interests: interests)
    }

    // MARK: - 불러오기 / 최초 생성

    static func fetchOrCreate(in context: ModelContext) throws -> UserProfile {
    // 저장된 프로필이 있으면 가져오고, 없으면 임시값으로 새로 만든다.
    // 프로필이 여러 개 생기지 않도록 항상 이 함수로 가져온다.
        var descriptor = FetchDescriptor<UserProfile>()
        // "UserProfile을 찾아 달라"는 검색 조건.
        descriptor.fetchLimit = 1
        // 하나만 있으면 되므로 최대 1개만 가져온다.
        if let existing = try context.fetch(descriptor).first {
            return existing
        }
        // 이미 저장된 프로필이 있으면 그대로 돌려준다.

        let profile = try UserProfile(
            departmentName: placeholderDepartmentName,
            interests: placeholderInterests
        )
        // 없으면 하드코딩한 임시값으로 만든다.
        // TODO: 온보딩 화면이 완성되면 이 부분을 온보딩 입력값으로 바꾼다.
        context.insert(profile)
        // 데이터베이스에 새 프로필을 넣는다.
        try context.save()
        // 바로 디스크에 저장한다.
        return profile
    }

    // MARK: - 검사

    private static func validatedDepartmentName(_ name: String) throws -> String {
    // 학과 이름을 검사하고 정리한다.
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        // 앞뒤 공백·줄바꿈을 지운다. 예: " 반도체공학과 " → "반도체공학과"
        guard !trimmed.isEmpty else { throw UserProfileError.emptyDepartmentName }
        // 비어 있으면 오류를 던진다.
        return trimmed
    }

    private static func validatedInterests(_ values: [String]) throws -> [String] {
    // 관심사 목록을 검사하고 정리한다.
        var unique: [String] = []
        // 중복을 뺀 결과를 담을 배열.
        for value in values {
        // 들어온 값을 하나씩 본다.
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            // 앞뒤 공백을 지운다.
            guard !trimmed.isEmpty else { throw UserProfileError.emptyInterest }
            // 빈 문자열이면 오류를 던진다.
            if !unique.contains(trimmed) { unique.append(trimmed) }
            // 처음 나온 값만 담는다. ["A", "A"]처럼 같은 값이 두 번 저장되지 않게 한다.
        }
        return unique
        // 통과한 목록을 돌려준다. 입력 순서는 그대로 유지된다.
    }
}

nonisolated struct UserProfileSnapshot: Equatable, Sendable {
// Foundation Model 등 다른 스레드에 넘길 수 있는 프로필 복사본.
// Sendable: 여러 스레드에서 동시에 써도 안전하다는 표시.
    let departmentName: String
    let interests: [String]

    var promptText: String {
    // Foundation Model 프롬프트에 그대로 넣을 수 있는 문장.
        "학과: \(departmentName)\n관심사: \(interests.joined(separator: ", "))"
        // 예: "학과: 반도체공학과\n관심사: A, P, Q"
    }
}

nonisolated enum UserProfileError: Error, Equatable {
// 프로필 규칙을 어겼을 때의 오류 종류.
    case emptyDepartmentName
    // 학과가 비어 있음.
    case emptyInterest
    // 관심사 중 빈 값이 있음.
}
