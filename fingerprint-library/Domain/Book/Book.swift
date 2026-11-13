//
//  Book.swift
//  2026-C6-M06-Fingerprint-library
//
//  Created by Youngmin Cho on 10/15/26.
//

import Foundation

nonisolated struct Book: Equatable, Identifiable, Sendable {
    let id: String
    let isbn: String?
    let controlNumber: String?
    let title: String
    let author: String
    let publisher: String?
    let publicationYear: String?
    let description: String?
    let imageURL: URL?
    var subLocation: String? = nil
    var resourceTypes: [String] = []
    
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

extension Book {
    nonisolated func replacingImageURL(_ imageURL: URL?) -> Book {
        var book = Book(
            id: id, isbn: isbn, controlNumber: controlNumber, title: title,
            author: author, publisher: publisher, publicationYear: publicationYear,
            description: description, imageURL: imageURL
        )
        book.subLocation = subLocation
        book.resourceTypes = resourceTypes
        return book
    }
}
