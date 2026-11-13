//
//  UserInterest.swift
//  fingerprint-library
//
//  Created by 이시온 on 10/28/26.
//

import Foundation

nonisolated enum UserInterest: String, CaseIterable, Codable, Identifiable, Sendable {
    case philosophyPsychologyReligion
    case archaeology
    case history
    case geographyAnthropology
    case socialSciences
    case politicalScience
    case law
    case education
    case music
    case fineArts
    case languageLiterature
    case science
    case medicine
    case agriculture
    case technology
    case militaryScience
    case navalScience

    var id: String { rawValue }

    var koreanName: String {
        switch self {
        case .philosophyPsychologyReligion: "철학・심리학・종교"
        case .archaeology: "고고학"
        case .history: "역사"
        case .geographyAnthropology: "지리학・인류학"
        case .socialSciences: "사회과학"
        case .politicalScience: "정치학"
        case .law: "법률"
        case .education: "교육"
        case .music: "음악"
        case .fineArts: "미술"
        case .languageLiterature: "언어・문학"
        case .science: "과학"
        case .medicine: "의학"
        case .agriculture: "농업"
        case .technology: "기술"
        case .militaryScience: "군사학"
        case .navalScience: "해군학"
        }
    }

    var lccClasses: [String] {
        switch self {
        case .philosophyPsychologyReligion: ["B"]
        case .archaeology: ["C"]
        case .history: ["D", "E", "F"]
        case .geographyAnthropology: ["G"]
        case .socialSciences: ["H"]
        case .politicalScience: ["J"]
        case .law: ["K"]
        case .education: ["L"]
        case .music: ["M"]
        case .fineArts: ["N"]
        case .languageLiterature: ["P"]
        case .science: ["Q"]
        case .medicine: ["R"]
        case .agriculture: ["S"]
        case .technology: ["T"]
        case .militaryScience: ["U"]
        case .navalScience: ["V"]
        }
    }

    static func lccClasses(for interests: [UserInterest]) -> [String] {
        interests.flatMap(\.lccClasses)
    }
}
