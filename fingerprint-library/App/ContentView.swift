import SwiftUI
import Playgrounds

struct ContentView: View {
    @State private var searchText = ""
    
    var body: some View {
        NavigationStack {
            List {
                Text("검색 결과")
            }
            .navigationTitle("핑프")
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "책 검색 해보삼"
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
