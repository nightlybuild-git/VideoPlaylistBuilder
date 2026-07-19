import SwiftUI

struct ContentView: View {
    @Environment(PlaylistStore.self) private var store

    var body: some View {
        @Bindable var store = store
        NavigationStack(path: $store.navPath) {
            BoardView()
                .navigationDestination(for: Playlist.ID.self) { id in
                    if let playlist = store.playlists.first(where: { $0.id == id }) {
                        PlaylistDetailView(playlist: playlist)
                    }
                }
        }
    }
}

#Preview {
    ContentView()
        .environment(PlaylistStore())
        .frame(width: 500, height: 560)
}
