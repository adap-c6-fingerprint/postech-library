/// 저장 모델을 다른 작업에 직접 넘기지 않도록 복사한 프로필 값.
nonisolated struct UserProfileSnapshot: Equatable, Sendable {
    let departmentName: String
    let interests: [String]

    var promptText: String {
        "학과: \(departmentName)\n관심사: \(interests.joined(separator: ", "))"
    }
}

nonisolated enum UserProfileError: Error, Equatable {
    case emptyDepartmentName
    case emptyInterest
}
