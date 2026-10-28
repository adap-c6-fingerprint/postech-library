//
//  LCCOutline.swift
//  fingerprint-library
//

import Foundation

nonisolated enum LCCOutline {
// 미국 의회도서관 분류(LCC)의 대분류 → 하위 분류 목록표.
// 포스텍 도서관 청구기호가 LCC를 쓰기 때문에 필요하다.

    static let subclasses: [String: [String]] = [
    // 키: 대분류 한 글자, 값: 그 대분류에 속한 분류기호 전체(대분류 자신 포함).
        "A": ["A", "AC", "AE", "AG", "AI", "AM", "AN", "AP", "AS", "AY", "AZ"],
        // 총류
        "B": ["B", "BC", "BD", "BF", "BH", "BJ", "BL", "BM", "BP", "BQ", "BR", "BS", "BT", "BV", "BX"],
        // 철학·심리학·종교
        "C": ["C", "CB", "CC", "CD", "CE", "CJ", "CN", "CR", "CS", "CT"],
        // 역사 보조학
        "D": ["D", "DA", "DAW", "DB", "DC", "DD", "DE", "DF", "DG", "DH", "DJ", "DJK", "DK", "DL",
              "DP", "DQ", "DR", "DS", "DT", "DU", "DX"],
        // 세계사
        "E": ["E"],
        // 미국사
        "F": ["F"],
        // 미국 지역사·아메리카사
        "G": ["G", "GA", "GB", "GC", "GE", "GF", "GN", "GR", "GT", "GV"],
        // 지리·인류학·레크리에이션
        "H": ["H", "HA", "HB", "HC", "HD", "HE", "HF", "HG", "HJ", "HM", "HN", "HQ", "HS", "HT", "HV", "HX"],
        // 사회과학
        "J": ["J", "JA", "JC", "JF", "JJ", "JK", "JL", "JN", "JQ", "JS", "JV", "JX", "JZ"],
        // 정치학
        "K": ["K", "KB", "KD", "KE", "KF", "KG", "KH", "KJ", "KK", "KL", "KM", "KN", "KP", "KQ",
              "KR", "KS", "KT", "KU", "KV", "KW", "KZ"],
        // 법학 (세 글자 분류는 생략)
        "L": ["L", "LA", "LB", "LC", "LD", "LE", "LF", "LG", "LH", "LJ", "LT"],
        // 교육
        "M": ["M", "ML", "MT"],
        // 음악
        "N": ["N", "NA", "NB", "NC", "ND", "NE", "NK", "NX"],
        // 미술
        "P": ["P", "PA", "PB", "PC", "PD", "PE", "PF", "PG", "PH", "PJ", "PK", "PL", "PM", "PN",
              "PQ", "PR", "PS", "PT", "PZ"],
        // 언어·문학
        "Q": ["Q", "QA", "QB", "QC", "QD", "QE", "QH", "QK", "QL", "QM", "QP", "QR"],
        // 과학
        "R": ["R", "RA", "RB", "RC", "RD", "RE", "RF", "RG", "RJ", "RK", "RL", "RM", "RS", "RT", "RV", "RX", "RZ"],
        // 의학
        "S": ["S", "SB", "SD", "SF", "SH", "SK"],
        // 농학
        "T": ["T", "TA", "TC", "TD", "TE", "TF", "TG", "TH", "TJ", "TK", "TL", "TN", "TP", "TR", "TS", "TT", "TX"],
        // 기술·공학
        "U": ["U", "UA", "UB", "UC", "UD", "UE", "UF", "UG", "UH"],
        // 군사학
        "V": ["V", "VA", "VB", "VC", "VD", "VE", "VF", "VG", "VK", "VM"],
        // 해군학
        "Z": ["Z", "ZA"]
        // 서지학·도서관학
    ]

    static func expand(_ code: String) -> [String] {
    // 관심 분류기호를 검색할 분류기호 목록으로 펼친다.
        if code.count == 1 {
            return subclasses[code] ?? [code]
            // 한 글자(대분류)면 하위 분류 전체. 예: "Q" → ["Q", "QA", …, "QR"]
            // 목록표에 없는 글자면 자기 자신만.
        }
        return [code]
        // 두세 글자(하위 분류)면 그대로. 예: "QC" → ["QC"]
    }
}
