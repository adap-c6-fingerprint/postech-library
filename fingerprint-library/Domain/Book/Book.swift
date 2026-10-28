//
//  Book.swift
//  2026-C6-M06-Fingerprint-library
//
//  Created by Youngmin Cho on 10/15/26.
//

import Foundation

struct Book: Equatable, Identifiable, Sendable {
    let id: String // 화면에서 각 도서를 구분하는 식별자
    let isbn: String? // 국제표준도서번호
    let controlNumber: String? // 도서관 자료 정보의 관리번호(제어번호)
    let title: String // 제목
    let author: String // 저자
    let publisher: String? // 출판사
    let publicationYear: String? // 출판 연도
    let description: String? // 설명
    let imageURL: URL? // 책 표지 URL
    
    nonisolated var recordKey: [String?] {
        if let controlNumber {
            return ["control", controlNumber]
        }
        
        let metadata: [String?] = [
            isbn, title, author, publisher, publicationYear
        ]
        
        return ["metadata"] + metadata.map { value -> String? in
            guard let value else { return nil }
            
            let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
            
            return text.isEmpty ? nil : text
        }
    }
}
