//
//  BookSearchResultRow.swift
//  fingerprint-library
//
//  Created by Youngmin Cho on 10/17/26.
//

import SwiftUI

struct BookSearchResultRow: View {
    let book: Book

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            coverImage

            VStack(alignment: .leading, spacing: 8) {
                Text(cleaned(book.title))
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(3)

                Text(cleaned(book.author))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                if !publicationInfo.isEmpty {
                    Text(publicationInfo)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.gray.opacity(0.15))
        }
    }

    private var coverImage: some View {
        AsyncImage(url: book.imageURL) { phase in
            if let image = phase.image {
                image
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "book.closed")
                    .font(.title)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 72, height: 104)
        .background(Color.gray.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .accessibilityHidden(true)
    }

    private var publicationInfo: String {
        let values = [book.publisher, book.publicationYear]

        return values.compactMap { value -> String? in
            guard let value else {
                return nil
            }

            let text = cleaned(value)
            return text.isEmpty ? nil : text
        }
        .joined(separator: " · ")
    }

    private func cleaned(_ text: String) -> String {
        return text
            .replacingOccurrences(
                of: #"</?span\b[^>]*>"#,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
            .replacingOccurrences(
                of: #"<br\s*/?>"#,
                with: " ",
                options: [.regularExpression, .caseInsensitive]
            )
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
