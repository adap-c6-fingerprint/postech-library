import ComposableArchitecture
import SwiftUI

struct HomeView: View {
    @Bindable var store: StoreOf<AppFeature>

    @State private var searchStore = Store(
        initialState: BookSearchFeature.State()
    ) {
        BookSearchFeature()
    }

    private var mapStore: StoreOf<IndoorMapFeature> {
        store.scope(state: \.indoorMap, action: \.indoorMap)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Fingerprint")
                        .font(.title2.weight(.semibold))

                    NavigationLink {
                        BookSearchView(store: searchStore)
                            .toolbar(.visible, for: .navigationBar)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "magnifyingglass")
                                .font(.title3)
                                .foregroundStyle(.primary)
                            Text("어떤 책을 찾으시나요?")
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal, 18)
                        .frame(minHeight: 52)
                        .background(Color(uiColor: .systemBackground), in: Capsule())
                        .overlay(Capsule().strokeBorder(Color(uiColor: .separator), lineWidth: 1))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("home-book-search")
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(uiColor: .systemBackground))

                IndoorMapView(store: mapStore)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(
                isPresented: Binding(
                    get: { store.isRouteSettingsPresented },
                    set: { store.send(.routeSettingsPresentationChanged($0)) }
                )
            ) {
                IndoorRouteSettingsView(store: mapStore)
            }
        }
        .tint(.primary)
    }
}

#Preview {
    AppView(store: Store(initialState: AppFeature.State()) { AppFeature() })
}
