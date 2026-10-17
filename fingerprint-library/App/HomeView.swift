import SwiftUI
import ComposableArchitecture

struct HomeView: View {
    let mapStore: StoreOf<IndoorMapFeature>

    @State private var store = Store(
        initialState: BookSearchFeature.State()
    ) {
        BookSearchFeature()
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {

                // 누르면 검색 화면으로 이동
                NavigationLink {
                    BookSearchView(store: store)
                        .toolbar(.visible, for: .navigationBar)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")

                        Text("어떤 책을 찾으시나요?")

                        Spacer()
                    }
                    .foregroundStyle(.secondary)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 24)
                            .fill(Color.gray.opacity(0.1))
                    )
                }
                .buttonStyle(.plain)

                IndoorMapView(store: mapStore)
                .clipShape(
                    RoundedRectangle(cornerRadius: 16)
                )
            }
            .padding()
            .navigationTitle("Fingerprint")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    HomeView(mapStore: Store(initialState: IndoorMapFeature.State()) {
        IndoorMapFeature()
    })
}
