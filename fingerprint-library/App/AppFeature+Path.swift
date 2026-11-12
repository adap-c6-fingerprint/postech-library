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

    /// 전체 화면으로 띄우는 안내. 어느 탭에서 요청해도 App이 하나만 띄운다.
    @Reducer
    enum Modal {
        case routePreview(BookRoutePreviewFeature)
    }

    /// 경로 미리보기를 요청한 스택 화면. 미리보기가 닫히면 그 화면에 알린다.
    struct GuidanceOrigin: Equatable {
        let tab: Tab
        let elementID: StackElementID
    }

    /// 경로 미리보기를 닫은 뒤, 요청한 상세 화면이 내려 둔 시트를 다시 띄우게 한다.
    func guidanceDismissed(state: inout State) -> Effect<Action> {
        guard let origin = state.guidanceOrigin else { return .none }
        state.guidanceOrigin = nil
        let action = StackActionOf<Path>.element(id: origin.elementID, action: .detail(.guidanceDismissed))
        switch origin.tab {
        case .map: return .send(.mapPath(action))
        case .recommendations: return .send(.recommendationsPath(action))
        case .search: return .send(.searchPath(action))
        }
    }

    /// 경로 미리보기를 연다. 여러 권은 방문 순서를 확인한 뒤 출발하고, 한 권은 바로 안내한다.
    func presentGuidance(for books: [Book], state: inout State) {
        guard !books.isEmpty else { return }
        state.modal = .routePreview(BookRoutePreviewFeature.State(
            books: books, entryMode: books.count > 1 ? .preview : .direct
        ))
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
        guard case let .element(elementID, action) = action else { return .none }
        switch action {
        case .favorites(.delegate(.showCart)):
            push(.cart(BookCartFeature.State()), onto: tab, state: &state)
        case let .myPage(.delegate(.showRecentlyFound(shelf))):
            push(.recentlyFound(shelf), onto: tab, state: &state)
        case let .recentlyFound(.delegate(.showDetail(book))):
            push(.detail(BookDetailFeature.State(book: book)), onto: tab, state: &state)
        case let .detail(.delegate(.startGuidance(books))):
            presentGuidance(for: books, state: &state)
            state.guidanceOrigin = GuidanceOrigin(tab: tab, elementID: elementID)
        case let .cart(.delegate(.startGuidance(books))),
             let .favoriteShelf(.delegate(.startGuidance(books))):
            presentGuidance(for: books, state: &state)
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
extension AppFeature.Modal.State: Equatable {}
