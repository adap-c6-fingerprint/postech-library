import Foundation
import SwiftData

/// SwiftData 저장 모델. 비동기 전달 값은 Domain으로 분리한다.
@Model
final class UserProfile {
    static let placeholderDepartmentName = "반도체공학과"
    static let placeholderInterests = ["A", "P", "Q"]

    private(set) var departmentName: String
    private(set) var interests: [String]

    init(departmentName: String, interests: [String]) throws {
        let department = try Self.validatedDepartmentName(departmentName)
        let validInterests = try Self.validatedInterests(interests)
        self.departmentName = department
        self.interests = validInterests
    }

    // MARK: - 설정 화면에서 수정

    func updateDepartmentName(_ name: String) throws {
        departmentName = try Self.validatedDepartmentName(name)
    }

    func updateInterests(_ newInterests: [String]) throws {
        interests = try Self.validatedInterests(newInterests)
    }

    // MARK: - Foundation Model 전달용

    var snapshot: UserProfileSnapshot {
        UserProfileSnapshot(departmentName: departmentName, interests: interests)
    }

    // MARK: - 불러오기 / 최초 생성

    /// 저장된 프로필이 없는 호출 경로에서만 기존 임시값을 만든다.
    static func fetchOrCreate(in context: ModelContext) throws -> UserProfile {
        var descriptor = FetchDescriptor<UserProfile>()
        descriptor.fetchLimit = 1
        if let existing = try context.fetch(descriptor).first {
            return existing
        }

        let profile = try UserProfile(
            departmentName: placeholderDepartmentName,
            interests: placeholderInterests
        )
        context.insert(profile)
        try context.save()
        return profile
    }

    // MARK: - 온보딩 저장

    static func exists(in context: ModelContext) throws -> Bool {
        var descriptor = FetchDescriptor<UserProfile>()
        descriptor.fetchLimit = 1
        return try !context.fetch(descriptor).isEmpty
    }

    static func save(departmentName: String, interests: [String], in context: ModelContext) throws {
        var descriptor = FetchDescriptor<UserProfile>()
        descriptor.fetchLimit = 1
        if let existing = try context.fetch(descriptor).first {
            try existing.updateDepartmentName(departmentName)
            try existing.updateInterests(interests)
        } else {
            context.insert(try UserProfile(departmentName: departmentName, interests: interests))
        }
        try context.save()
    }

    // MARK: - 검사

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
