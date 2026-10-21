//
//  BookBasketView.swift
//  fingerprint-library
//
//  Created by Youngmin Cho on 10/21/26.
//

import SwiftUI

struct BookBasketView: View {
    let books: [Book]
    let onDeletedSelected: (Set<Book.ID>) -> Void
    
    @State private var selectedBookIDs: Set<Book.ID> = []
    
    private var isAllSelected: Bool {
        !books.isEmpty && books.allSatisfy {
            selectedBookIDs.contains($0.id)
        }
    }
    
    var body: some View {
        List(books) { book in
            HStack(spacing: 12) {
                Button {
                    if selectedBookIDs.contains(book.id) {
                        selectedBookIDs.remove(book.id)
                    } else {
                        selectedBookIDs.insert(book.id)
                    }
                } label: {
                    Image(
                        systemName: selectedBookIDs.contains(book.id)
                        ? "checkmark.square"
                        : "square"
                    )
                    .font(.title2)
                    .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(book.title) 선택")
                .accessibilityValue(
                    selectedBookIDs.contains(book.id)
                    ? "선택됨"
                    : "선택 안 됨"
                )
                
                VStack(alignment: .leading, spacing: 6) {
                    Text(book.title)
                        .font(.headline)
                    
                    Text(book.author)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("책바구니")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack(spacing: 12) {
                Button {
                    if isAllSelected {
                        selectedBookIDs.removeAll()
                    } else {
                        selectedBookIDs = Set(books.map(\.id))
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(
                            systemName: isAllSelected
                            ? "checkmark.square"
                            : "square"
                        )
                        .font(.title2)
                        .frame(width: 44, height: 44)
                        
                        Text("전체 선택")
                            .font(.headline)
                    }
                }
                .buttonStyle(.plain)
                .disabled(books.isEmpty)
                .accessibilityValue(
                    isAllSelected ? "전체 선택됨" : "전체 선택 안 됨"
                )
                
                Spacer()
                
                Button(role: .destructive) {
                    onDeletedSelected(selectedBookIDs)
                    selectedBookIDs.removeAll()
                } label: {
                    Text("선택 삭제")
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .disabled(selectedBookIDs.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(.systemGroupedBackground))
        }
    }
}
