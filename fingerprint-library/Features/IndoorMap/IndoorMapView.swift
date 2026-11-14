import ComposableArchitecture
import SwiftUI

struct IndoorMapView: View {
    struct BookDetailPresentation {
        let floor: IndoorMapFloor?
        let shelves: [IndoorShelfLabel]
        let cameraRequest: IndoorMapCameraRequest?
    }

    let store: StoreOf<IndoorMapFeature>
    @State private var homeMarkerCache = HomeMapMarkerCache()
    var bottomContentInset: CGFloat = 0
    var topContentInset: CGFloat = 0
    var appearance: IndoorMapKitView.Appearance = .standard
    var highlightedFeatureIDs: Set<IndoorMapElement.ID> = []
    var showsCurrentLocationButton = true
    var showsFloorPicker = true
    var extendsUnderBottomSafeArea = true
    var bookDetail: BookDetailPresentation?
    var onSelectFavoriteMarker: (HomeMapMarker) -> Void = { _ in }
    var homeAnnotations: HomeMapAnnotationsFeature.State?
    var hiddenFavoriteMarkerIDs: Set<String> = []

    var body: some View {
        Group {
            if let map = store.map, let floor = bookDetail?.floor ?? store.selectedFloor {
                mapContent(map: map, floor: floor)
            } else if store.isLoading {
                ProgressView("실내지도를 불러오고 있어요")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView {
                    Label("지도를 불러오지 못했어요", systemImage: "map")
                } description: {
                    Text(store.loadError ?? "도서관 지도를 불러올 수 없어요. 다시 시도해주세요.")
                } actions: {
                    Button("다시 시도") { store.send(.retryTapped) }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private func mapContent(map: IndoorMap, floor: IndoorMapFloor) -> some View {
        ZStack(alignment: .bottomTrailing) {
            IndoorMapKitView(
                map: map, floor: floor,
                position: store.currentPosition,
                showsUserLocation: store.showsNativeUserLocation,
                cameraRequest: cameraRequest(for: floor),
                viewportInsets: .init(top: 60 + topContentInset, left: appearance == .home ? 77 : 0,
                                      bottom: bottomContentInset, right: 0),
                shelfLabels: store.shelfLabels,
                highlightedFeatureIDs: bookDetail.map { Set($0.shelves.map(\.mapElementID)) } ?? highlightedFeatureIDs,
                appearance: bookDetail == nil ? appearance : .bookDetail,
                homeMarkers: homeMarkers(on: map),
                onSelectFavoriteMarker: onSelectFavoriteMarker,
                detailShelfLabels: bookDetail?.shelves ?? []
            )
            .ignoresSafeArea(.container, edges: extendsUnderBottomSafeArea ? .bottom : [])

            VStack(alignment: .leading, spacing: 12) {
                if showsCurrentLocationButton, appearance == .standard {
                    HStack {
                        Spacer()
                        currentLocationButton
                    }
                }

                if let message = store.locationMessage {
                    Text(message)
                        .font(.caption)
                        .padding(10)
                        .background(
                            Color(uiColor: .systemBackground),
                            in: RoundedRectangle(cornerRadius: 12)
                        )
                        .accessibilityIdentifier("map-location-status")
                }

                if let message = store.shelfLabelError {
                    HStack {
                        Text(message)
                        Button("다시 시도") { store.send(.retryShelfLabelsTapped) }
                    }
                    .font(.caption)
                    .padding(10)
                    .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityIdentifier("map-shelf-label-status")
                }

                Spacer(minLength: 0)
                HStack(alignment: .bottom, spacing: 12) {
                    VStack(alignment: .leading, spacing: 12) {
                        if appearance == .home { amenitiesButton }
                        if showsFloorPicker {
                            floorPicker(map: map, floor: floor)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.trailing, appearance == .home && showsCurrentLocationButton ? 62 : 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.leading, 16)
            .padding(.trailing, appearance == .home ? 25 : 16)
            .padding(.top, 16 + topContentInset)
            .padding(.bottom, (appearance == .home ? 20 : 16) + bottomContentInset)

            if appearance == .home, showsCurrentLocationButton {
                currentLocationButton
                    .padding(.trailing, 25)
                    .padding(.bottom, 20 + bottomContentInset)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var amenitiesButton: some View {
        Button { store.send(.homeAnnotations(.amenitiesTapped)) } label: {
            HStack(alignment: .center, spacing: 10) {
                Text("편의시설")
                    .typography(.caption2)
                    .foregroundStyle(store.homeAnnotations.showsAmenities
                                     ? PobookUI.ColorToken.primaryLight : PobookUI.ColorToken.neutralPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.25)
            }
            .padding(.horizontal, 4)
            .frame(width: 61, height: 34, alignment: .center)
            .background(Color(red: 0.6, green: 0.6, blue: 0.6).opacity(0.17))
            .cornerRadius(12)
            .glassEffect(.regular, in: .rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("map-amenities")
        .accessibilityValue(store.homeAnnotations.showsAmenities ? "전체 시설 표시 중" : "기본 아이콘만 표시 중")
    }

    private func cameraRequest(for floor: IndoorMapFloor) -> IndoorMapCameraRequest? {
        guard let bookDetail else { return store.cameraRequest }
        return bookDetail.cameraRequest ?? .init(id: 0, target: .initialFloor(floor.id))
    }

    private func homeMarkers(on map: IndoorMap) -> [HomeMapMarker] {
        guard appearance == .home || bookDetail != nil else { return [] }
        let annotations = homeAnnotations ?? store.homeAnnotations
        return homeMarkerCache.markers(on: map, labels: store.shelfLabels,
            holdings: annotations.holdings, showsAmenities: annotations.showsAmenities,
            hidingFavoritesFor: bookDetail?.shelves ?? [], hiddenFavoriteMarkerIDs: hiddenFavoriteMarkerIDs)
    }

    @ViewBuilder private var currentLocationButton: some View {
        if appearance == .home {
            MapRecenterButton { store.send(.currentLocationTapped) }
        } else {
            Button { store.send(.currentLocationTapped) } label: {
                Image(systemName: "scope").font(.title3.weight(.medium))
                .frame(minWidth: 48, minHeight: 48)
                .background(Color(uiColor: .systemBackground), in: Capsule())
                .overlay(Capsule().strokeBorder(Color(uiColor: .separator).opacity(0.4)))
                .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("현재 위치로 지도 이동")
            .accessibilityIdentifier("recenter-location")
        }
    }

    private func floorPicker(map: IndoorMap, floor: IndoorMapFloor) -> some View {
        IndoorMapFloorPicker(
            floors: map.floors, selectedFloorID: floor.id, appearance: appearance,
            onSelect: { store.send(.floorSelected($0)) })
    }
}
