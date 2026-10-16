//
//  Book.swift
//  2026-C6-M06-Fingerprint-library
//
//  Created by Youngmin Cho on 10/15/26.
//

import Foundation

struct Book: Equatable, Identifiable, Sendable {
    let isbn: String // 책의 고유 식별 아이디
    let title: String // 제목
    let author: String // 저자
    let publisher: String? // 출판사
    let publicationYear: String? // 출판 연도
    let description: String? // 설명
    let imageURL: URL? // 책 표지 URL
    
    var id: String {
        isbn
    }
}
