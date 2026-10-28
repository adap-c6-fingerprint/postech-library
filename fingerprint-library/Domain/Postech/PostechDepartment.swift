//
//  PostechDepartment.swift
//  fingerprint-library
//
//  Created by 이시온 on 10/28/26.
//

import Foundation

enum PostechDepartment: Hashable, Sendable {
    case undergraduate(Undergraduate)
    case graduate(Graduate)
    // 학부·대학원은 같은 이름의 학과가 있어도 별개의 소속으로 구분

    var koreanName: String {
        switch self {
        case .undergraduate(let department): department.koreanName
        case .graduate(let department): department.koreanName
        }
    }

    var englishName: String {
        switch self {
        case .undergraduate(let department): department.englishName
        case .graduate(let department): department.englishName
        }
    }

    var status: PostechStatus {
        switch self {
        case .undergraduate: .undergraduate
        case .graduate: .graduate
        }
    }
    // 학과가 속한 신분. 저장된 학과가 선택한 신분과 맞는지 검사할 때 사용

    static var allCases: [PostechDepartment] {
        Undergraduate.allCases.map(PostechDepartment.undergraduate)
            + Graduate.allCases.map(PostechDepartment.graduate)
    }
}

// MARK: - 학부

extension PostechDepartment {
    enum Undergraduate: String, CaseIterable, Codable, Identifiable, Sendable {
        case mathematics
        case physics
        case chemistry
        case lifeSciences
        case materialsScience
        case mechanicalEngineering
        case industrialManagementEngineering
        case electricalEngineering
        case computerScience
        case chemicalEngineering
        case biomedicalEngineering
        case semiconductorEngineering
        case humanitiesSocialSciences

        enum Field: String, CaseIterable, Codable, Sendable {
            case naturalScience
            case engineering
            case division

            var koreanName: String {
                switch self {
                case .naturalScience: "자연과학"
                case .engineering: "공학"
                case .division: "학부"
                }
            }
        }

        var id: String { rawValue }

        var field: Field {
            switch self {
            case .mathematics, .physics, .chemistry, .lifeSciences:
                .naturalScience
            case .materialsScience, .mechanicalEngineering, .industrialManagementEngineering,
                 .electricalEngineering, .computerScience, .chemicalEngineering,
                 .biomedicalEngineering, .semiconductorEngineering:
                .engineering
            case .humanitiesSocialSciences:
                .division
            }
        }

        var koreanName: String {
            switch self {
            case .mathematics: "수학과"
            case .physics: "물리학과"
            case .chemistry: "화학과"
            case .lifeSciences: "생명과학과"
            case .materialsScience: "신소재공학과"
            case .mechanicalEngineering: "기계공학과"
            case .industrialManagementEngineering: "산업경영공학과"
            case .electricalEngineering: "전자전기공학과"
            case .computerScience: "컴퓨터공학과"
            case .chemicalEngineering: "화학공학과"
            case .biomedicalEngineering: "바이오메디컬공학과"
            case .semiconductorEngineering: "반도체공학과"
            case .humanitiesSocialSciences: "인문사회학부"
            }
        }

        var englishName: String {
            switch self {
            case .mathematics: "Mathematics"
            case .physics: "Physics"
            case .chemistry: "Chemistry"
            case .lifeSciences: "Life Sciences"
            case .materialsScience: "Materials Science & Engineering"
            case .mechanicalEngineering: "Mechanical Engineering"
            case .industrialManagementEngineering: "Industrial & Management Engineering"
            case .electricalEngineering: "Electrical Engineering"
            case .computerScience: "Computer Science & Engineering"
            case .chemicalEngineering: "Chemical Engineering"
            case .biomedicalEngineering: "Biomedical Engineering"
            // 예전 명칭: CiTE
            case .semiconductorEngineering: "Semiconductor Engineering"
            case .humanitiesSocialSciences: "Division of Humanities & Social Sciences"
            }
        }
    }
}

// MARK: - 대학원

extension PostechDepartment {
    enum Graduate: String, CaseIterable, Codable, Identifiable, Sendable {
        case mathematics
        case physics
        case chemistry
        case lifeSciences
        case materialsScience
        case mechanicalEngineering
        case industrialManagementEngineering
        case chemicalEngineering
        case electricalEngineering
        case computerScience
        case semiconductor
        case environmentalScience
        case artificialIntelligence
        case advancedNuclearEngineering
        case convergenceScience
        case advancedMaterialsScience
        case biomedicalEngineering
        case interdisciplinaryBioscience
        case technologyInnovationManagement
        case informationTechnology
        case ferrousEcoMaterials

        enum School: String, CaseIterable, Codable, Sendable {
            case general
            case professional
            case special

            var koreanName: String {
                switch self {
                case .general: "일반대학원"
                case .professional: "전문대학원"
                case .special: "특수대학원"
                }
            }
        }

        var id: String { rawValue }

        var school: School {
            switch self {
            case .informationTechnology: .professional
            case .ferrousEcoMaterials: .special
            default: .general
            }
        }

        var abbreviation: String? {
            switch self {
            case .environmentalScience: "DESE"
            case .advancedNuclearEngineering: "DANE"
            case .advancedMaterialsScience: "AMS"
            case .interdisciplinaryBioscience: "I-Bio"
            case .technologyInnovationManagement: "TIM"
            case .informationTechnology: "GSIT"
            case .ferrousEcoMaterials: "GIFT"
            default: nil
            }
        }

        var koreanName: String {
            switch self {
            case .mathematics: "수학과"
            case .physics: "물리학과"
            case .chemistry: "화학과"
            case .lifeSciences: "생명과학과"
            case .materialsScience: "신소재공학과"
            case .mechanicalEngineering: "기계공학과"
            case .industrialManagementEngineering: "산업경영공학과"
            case .chemicalEngineering: "화학공학과"
            case .electricalEngineering: "전자전기공학과"
            case .computerScience: "컴퓨터공학과"
            case .semiconductor: "반도체대학원"
            case .environmentalScience: "환경공학부"
            case .artificialIntelligence: "인공지능대학원"
            case .advancedNuclearEngineering: "첨단원자력공학부"
            case .convergenceScience: "융합대학원"
            case .advancedMaterialsScience: "첨단재료과학부"
            case .biomedicalEngineering: "바이오메디컬공학"
            case .interdisciplinaryBioscience: "융합생명공학부"
            case .technologyInnovationManagement: "기술경영 대학원과정"
            case .informationTechnology: "정보통신대학원"
            case .ferrousEcoMaterials: "철강·친환경소재대학원"
            }
        }

        var englishName: String {
            switch self {
            case .mathematics: "Mathematics"
            case .physics: "Physics"
            case .chemistry: "Chemistry"
            case .lifeSciences: "Life Sciences"
            case .materialsScience: "Materials Science & Engineering"
            case .mechanicalEngineering: "Mechanical Engineering"
            case .industrialManagementEngineering: "Industrial & Management Engineering"
            case .chemicalEngineering: "Chemical Engineering"
            case .electricalEngineering: "Electrical Engineering"
            case .computerScience: "Computer Science & Engineering"
            case .semiconductor: "Graduate School of Semiconductor Engineering"
            case .environmentalScience: "Division of Environmental Science & Engineering"
            case .artificialIntelligence: "Graduate School of Artificial Intelligence"
            case .advancedNuclearEngineering: "Division of Advanced Nuclear Engineering"
            case .convergenceScience: "School of Convergence Science and Technology"
            case .advancedMaterialsScience: "Division of Advanced Materials Science"
            case .biomedicalEngineering: "Biomedical Engineering"
            case .interdisciplinaryBioscience: "Division of Interdisciplinary Bioscience & Bioengineering"
            case .technologyInnovationManagement: "Graduate Program for Technology & Innovation Management"
            case .informationTechnology: "Graduate School of Information Technology"
            case .ferrousEcoMaterials: "Graduate Institute of Ferrous & Eco Materials Technology"
            }
        }
    }
}
