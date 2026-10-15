//
//  Book.swift
//  2026-C6-M06-Fingerprint-library
//
//  Created by Youngmin Cho on 10/15/26.
//

import Foundation

struct Book: Equatable, Identifiable, Sendable {
    let isbn: String
    let title: String
    let author: String
    let publisher: String?
    let publicationYear: String?
    let description: String?
    let imageURL: URL?
    
    var id: String {
        isbn
    }
}
