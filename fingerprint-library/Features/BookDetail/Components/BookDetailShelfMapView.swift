import ComposableArchitecture
import SwiftUI

struct BookDetailShelfMapView: View {
    let store: StoreOf<IndoorMapFeature>
    let floor: IndoorMapFloor?
    let shelves: [IndoorShelfLabel]
    let mapSize: CGSize
    let bottomContentInset: CGFloat
    let isReadyToFocus: Bool
    var homeAnnotations: HomeMapAnnotationsFeature.State?
    var hiddenFavoriteMarkerIDs: Set<String> = []

    @State private var camera: IndoorMapCameraRequest?

    private struct Focus: Equatable {
        let featureIDs: [IndoorMapElement.ID]
        let mapSize: CGSize
        let bottomInset: CGFloat
    }

    private var focus: Focus? {
        guard isReadyToFocus, !shelves.isEmpty else { return nil }
        return .init(featureIDs: shelves.map(\.mapElementID), mapSize: mapSize, bottomInset: bottomContentInset)
    }

    var body: some View {
        let target = focus.map { IndoorMapCameraRequest.Target.features($0.featureIDs) }
        IndoorMapView(
            store: store, showsDestinationCard: false, showsRoute: false,
            bottomContentInset: bottomContentInset,
            showsCurrentLocationButton: false, showsFloorPicker: false,
            bookDetail: .init(floor: floor, shelves: shelves,
                cameraRequest: camera?.target == target ? camera : nil),
            homeAnnotations: homeAnnotations, hiddenFavoriteMarkerIDs: hiddenFavoriteMarkerIDs
        )
        .ignoresSafeArea(.container, edges: .top)
        .onChange(of: focus, initial: true) { _, focus in
            guard let focus else { return }
            camera = .init(id: (camera?.id ?? 0) + 1, target: .features(focus.featureIDs))
        }
    }
}
