//
//  BookFavoriteItem+Codable.swift
//  fingerprint-library
//
//  찜 기록 저장 형식. 이전 BookFavoritesClient가 UserDefaults "favoriteBookItems"에 쓰던 JSON과
//  키 이름·구조를 똑같이 맞춰, 기존 사용자의 찜 기록을 옮기지 않고 그대로 읽는다.
//  검색 응답에서만 오는 subLocation·resourceTypes는 이전처럼 저장하지 않는다.
//

import Foundation

extension BookFavoriteItem: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, isbn, controlNumber, title, author, publisher, publicationYear, description, imageURL, favoritedAt
    }

    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            book: Book(
                id: try container.decode(String.self, forKey: .id),
                isbn: try container.decodeIfPresent(String.self, forKey: .isbn),
                controlNumber: try container.decodeIfPresent(String.self, forKey: .controlNumber),
                title: try container.decode(String.self, forKey: .title),
                author: try container.decode(String.self, forKey: .author),
                publisher: try container.decodeIfPresent(String.self, forKey: .publisher),
                publicationYear: try container.decodeIfPresent(String.self, forKey: .publicationYear),
                description: try container.decodeIfPresent(String.self, forKey: .description),
                imageURL: try container.decodeIfPresent(URL.self, forKey: .imageURL)
            ),
            favoritedAt: try container.decode(Date.self, forKey: .favoritedAt)
        )
    }

    nonisolated func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(book.id, forKey: .id)
        try container.encodeIfPresent(book.isbn, forKey: .isbn)
        try container.encodeIfPresent(book.controlNumber, forKey: .controlNumber)
        try container.encode(book.title, forKey: .title)
        try container.encode(book.author, forKey: .author)
        try container.encodeIfPresent(book.publisher, forKey: .publisher)
        try container.encodeIfPresent(book.publicationYear, forKey: .publicationYear)
        try container.encodeIfPresent(book.description, forKey: .description)
        try container.encodeIfPresent(book.imageURL, forKey: .imageURL)
        try container.encode(favoritedAt, forKey: .favoritedAt)
    }
}
