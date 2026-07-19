import SwiftUI

@main
struct VideoPlaylistBuilderApp: App {
    @State private var store = PlaylistStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .frame(minWidth: 300, minHeight: 280)
        }
        .defaultSize(width: 480, height: 560)
        .commands { PlaylistCommands(store: store) }

        Settings {
            SettingsView()
        }
    }
}

// MARK: - Menu bar

private struct PlaylistCommands: Commands {
    @Bindable var store: PlaylistStore

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Playlist…") { store.promptNewPlaylist() }
                .keyboardShortcut("n", modifiers: .command)
            Button("Add Existing Playlist…") { store.promptAddPlaylist() }
                .keyboardShortcut("o", modifiers: [.command, .shift])
        }

        CommandGroup(replacing: .undoRedo) {
            Button("Undo Last Change") {
                if let playlist = store.selectedPlaylist { store.undo(playlist) }
            }
            .keyboardShortcut("z", modifiers: .command)
            .disabled(!(store.selectedPlaylist?.canUndo ?? false))
        }

        CommandMenu("Playlist") {
            Button("Play") {
                if let playlist = store.selectedPlaylist { store.play(playlist) }
            }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(store.selectedPlaylist?.entries.isEmpty ?? true)

            Button("Add Videos…") {
                if let playlist = store.selectedPlaylist { store.promptAddVideos(to: playlist) }
            }
            .keyboardShortcut("a", modifiers: [.command, .shift])
            .disabled(store.selectedPlaylist == nil)

            Button("Reveal in Finder") {
                if let playlist = store.selectedPlaylist { store.reveal(playlist) }
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(store.selectedPlaylist == nil)

            Divider()

            Button("Remove from List") {
                if let playlist = store.selectedPlaylist { store.removePlaylist(playlist) }
            }
            .disabled(store.selectedPlaylist == nil)
        }
    }
}

// MARK: - Settings

struct SettingsView: View {
    @AppStorage("readDurations") private var readDurations = true

    var body: some View {
        Form {
            Section {
                Toggle("Read durations from video files when adding", isOn: $readDurations)
            } footer: {
                Text("Reads each video's length so entries use a real #EXTINF duration. Turn off for faster adds when you don't need durations.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 160)
    }
}
