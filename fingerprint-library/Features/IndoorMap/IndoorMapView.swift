import ComposableArchitecture
import SwiftUI

struct IndoorMapView: View {
    let store: StoreOf<IndoorMapFeature>
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if let map = store.map, let floor = store.selectedFloor {
                mapContent(map: map, floor: floor)
            } else if store.isLoading {
                ProgressView("실내지도를 불러오고 있어요")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView {
                    Label("지도를 불러오지 못했어요", systemImage: "map")
                } description: {
                    Text("C5 테스트 도면을 준비한 뒤 다시 시도해주세요.")
                } actions: {
                    Button("다시 시도") { store.send(.retryTapped) }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await store.send(.task).finish() }
        .onDisappear { store.send(.disappeared) }
        .onChange(of: scenePhase) { _, phase in store.send(.sceneActiveChanged(phase == .active)) }
    }

    private func mapContent(map: IndoorMap, floor: IndoorMapFloor) -> some View {
        ZStack {
            IndoorMapKitView(
                map: map, floor: floor, selectedFeatureID: nil,
                position: store.currentPosition, showsUserLocation: store.showsNativeUserLocation,
                isPlacingOrigin: false, cameraRequest: store.cameraRequest,
                onSelect: { _ in },
                onPlaceOrigin: { _ in },
                shelves: store.mockShelves,
                selectedShelfKey: store.selectedShelfKey,
                onSelectShelf: { store.send(.shelfSelected($0)) },
                route: store.route
            )
            .ignoresSafeArea()

            HStack {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(map.floors.reversed()) { item in
                            Button {
                                store.send(.floorSelected(item.id))
                            } label: {
                                Text(item.name)
                                    .font(.subheadline.weight(item.id == floor.id ? .bold : .regular))
                                    .frame(minWidth: 44, minHeight: 44)
                                    .padding(.horizontal, 4)
                                    .background(item.id == floor.id ? Color(uiColor: .label) : Color.clear)
                                    .foregroundStyle(item.id == floor.id ? Color(uiColor: .systemBackground) : .primary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(item.name) 지도 보기")
                            .accessibilityAddTraits(item.id == floor.id ? [.isSelected] : [])
                            .accessibilityIdentifier("floor-\(item.ordinal)")
                        }
                    }
                }
                .frame(width: 60, height: min(CGFloat(map.floors.count) * 44, 264))
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 13))
                .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
                Spacer()
            }
            .padding(.horizontal, 12)

            VStack {
                Spacer()
                IndoorRouteControls(store: store)
                    .padding(.horizontal, 12)
                    .padding(.bottom, IndoorLocationClient.usesSimulation ? 60 : 12)
            }

            #if DEBUG && targetEnvironment(simulator)
            if IndoorLocationClient.usesSimulation {
                VStack {
                    Spacer()
                    Text(store.locationMessage ?? "시뮬레이션 위치")
                        .font(.caption)
                        .padding(8)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.bottom, 12)
                        .accessibilityIdentifier("simulation-location-status")
                }
                .allowsHitTesting(false)
            }
            #endif
        }
    }
}
