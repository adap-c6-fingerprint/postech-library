import SwiftUI
import Playgrounds

struct ContentView: View {
    @State private var searchText = ""
    
    var body: some View {
        NavigationStack {
            List {
                Text("여기에 책 뜰 예정")
                    .font(.largeTitle)
            }
            .navigationTitle("핑프")
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "책 검색"
            )
        }
    }
}

#Preview {
    ContentView()
}

#Playground {
    _ = 1 + 2
}
