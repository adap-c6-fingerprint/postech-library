//
//  BookSearchFeature.swift
//  fingerprint-library
//
//  Created by Youngmin Cho on 10/15/26.
//

import Foundation
import ComposableArchitecture

@Reducer
struct BookSearchFeature {
    
    // 화면과 검색 로직에 필요한 데이터
    @ObservableState
    struct State: Equatable {
        var query: String = ""
        var books: [Book] = []
        var isLoading: Bool = false
        var errorMessage: String? = nil
        var hasSearched: Bool = false
    }
    
    // 이 기능에서 발생할 수 있는 이벤트
    enum Action {
        case queryChanged(String)
        case searchButtonTapped
        case searchSucceeded([Book])
        case searchFailed(String)
    }
    
    // 검색에 사용할 BookClient 값
    @Dependency(\.bookClient)
    var bookClient: BookClient
    
    // Action을 받아 State를 바꾸고, 필요한 Effect를 반환
    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
                
            case let .queryChanged(query):
                state.query = query
                return .none
                
            case .searchButtonTapped:
                // 이미 검색 중이면 추가 요청을 보내지 않음
                guard !state.isLoading else {
                    return .none
                }
                
                let keyword = state.query.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                
                // 빈 검색어는 통신 없이 처리
                guard !keyword.isEmpty else {
                    state.books = []
                    state.errorMessage = nil
                    state.hasSearched = false
                    return .none
                }
                
                state.isLoading = true
                state.errorMessage = nil
                state.books = []
                state.hasSearched = true
                
                // 검색할 작업을 담은 Effect 값을 만들어 반환
                return .run { [bookClient] send in
                    do {
                        // Store가 Effect를 실행하면 이 코드가 동작
                        let books = try await bookClient.search(keyword)
                        
                        // 검색 결과를 새로운 Action으로 보냄
                        await send(.searchSucceeded(books))
                    } catch {
                        await send(
                            .searchFailed(error.localizedDescription)
                        )
                    }
                }
                
            case let .searchSucceeded(books):
                // 화면 ID가 모두 다른지 확인
                assert(Set(books.map(\.id)).count == books.count)
                
                // 제어번호가 있는 항목끼리 중복되는지 확인
                let controlNumber = books.compactMap(\.controlNumber)
                assert(Set(controlNumber).count == controlNumber.count)
                
                state.isLoading = false
                state.books = books
                return .none
                
            case let .searchFailed(message):
                state.isLoading = false
                state.errorMessage = message
                return .none
            }
        }
    }
}

struct BookSearch {
    @Dependency(\.bookClient) var bookClient: BookClient
    
    func searchBooks(query: String) async throws -> [Book] {
        let keyword: String = query.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        
        if keyword.isEmpty {
            return []
        }
        
        let books: [Book] = try await bookClient.search(keyword)
        
        return books
    }
}
