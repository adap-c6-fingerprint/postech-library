//
//  AppFeature+Path.swift
//  fingerprint-library
//
//  탭마다 App이 소유하는 push 화면 스택. 기능은 delegate로 이동을 요청하고,
//  App이 요청이 생긴 탭의 스택에 화면을 쌓는다.
//

import ComposableArchitecture
import Foundation

extension AppFeature {
    @Reducer
    enum Path {
        case detail(BookDetailFeature)
        case cart(BookCartFeature)
        case favorites(BookFavoritesFeature)
        case favoriteShelf(BookShelfMapFeature)
        case myPage(MyPageFeature)
        case recentlyFound(RecentlyFoundBookFeature)
        case departmentRecommendations(DepartmentRecommendationsDestination)
    }

    /// 화면 이동 요청을 해당 탭의 스택에 반영한다.
    func push(_ destination: Path.State, onto tab: Tab, state: inout State) {
        switch tab {
        case .map: state.mapPath.append(destination)
        case .recommendations: state.recommendationsPath.append(destination)
        case .search: state.searchPath.append(destination)
        }
    }

    /// 스택에 쌓인 화면이 보낸 이동 요청을 같은 탭의 스택에 이어 쌓는다.
    func handlePath(_ action: StackActionOf<Path>, on tab: Tab, state: inout State) -> Effect<Action> {
        guard case let .element(_, action) = action else { return .none }
        switch action {
        case .favorites(.delegate(.showCart)):
            push(.cart(BookCartFeature.State()), onto: tab, state: &state)
        case let .myPage(.delegate(.showRecentlyFound(shelf))):
            push(.recentlyFound(shelf), onto: tab, state: &state)
        case let .recentlyFound(.delegate(.showDetail(book))):
            push(.detail(BookDetailFeature.State(book: book)), onto: tab, state: &state)
        default:
            break
        }
        return .none
    }

    static func destination(for delegate: HomeFeature.Action.Delegate) -> Path.State {
        switch delegate {
        case let .showDetail(book, cachedCoverURL):
            .detail(BookDetailFeature.State(book: book, cachedCoverURL: cachedCoverURL))
        case .showCart:
            .cart(BookCartFeature.State())
        case .showFavorites:
            .favorites(BookFavoritesFeature.State())
        case .showMyPage:
            .myPage(MyPageFeature.State())
        case .showDepartmentRecommendations:
            .departmentRecommendations(DepartmentRecommendationsDestination.State())
        }
    }

    /// 검색 delegate 중 화면 이동 요청만 목적지로 바꾼다. 그 밖의 요청은 nil이다.
    static func destination(for delegate: BookSearchFeature.Action.Delegate) -> Path.State? {
        switch delegate {
        case let .showDetail(book, markerID):
            var detail = BookDetailFeature.State(book: book)
            detail.sourceFavoriteMarkerID = markerID
            return .detail(detail)
        case let .showFavoriteShelf(books, markerID):
            guard var shelf = BookShelfMapFeature.State(previewing: books) else { return nil }
            shelf.sourceFavoriteMarkerID = markerID
            return .favoriteShelf(shelf)
        case .showCart:
            return .cart(BookCartFeature.State())
        case .showFavorites:
            return .favorites(BookFavoritesFeature.State())
        case .showMyPage:
            return .myPage(MyPageFeature.State())
        case .recommendationLayoutRequested, .kulumiCoversRequested:
            return nil
        }
    }
}

extension AppFeature.Path.State: Equatable {}
