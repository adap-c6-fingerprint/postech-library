//
//  BookBasketView.swift
//  fingerprint-library
//
//  Created by Youngmin Cho on 10/21/26.
//

import SwiftUI

struct BookBasketView: View {
    let books: [Book]
    
    var body: some View {
        List(books) { book in
            VStack(alignment: .leading, spacing: 6) {
                Text(book.title)
                    .font(.headline)
                
                Text(book.author)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("책바구니")
        .navigationBarTitleDisplayMode(.inline)
    }
}
