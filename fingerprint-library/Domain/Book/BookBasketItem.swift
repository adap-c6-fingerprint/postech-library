//
//  BookBasketItem.swift
//  fingerprint-library
//

import Foundation

// 장바구니에 보관한 책과 보관한 시각
struct BookBasketItem: Equatable, Identifiable, Sendable {
    let book: Book
    let addedAt: Date

    var id: Book.ID { book.id }
}
