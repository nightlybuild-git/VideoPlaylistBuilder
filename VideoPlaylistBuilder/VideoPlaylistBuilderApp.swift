import SwiftUI
import AppKit

@main
struct VideoPlaylistBuilderApp: App {
    @State private var store = PlaylistStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .frame(minWidth: 300, minHeight: 280)
                // Utility footprint: on first launch, open compact in the upper-
                // left corner so it sits beside the Finder window you're dragging
                // from. After that, the window remembers where you put it.
                .background(WindowConfigurator())
        }
        .defaultSize(width: 360, height: 420)
        .commands { PlaylistCommands(store: store) }

        Settings {
            SettingsView()
        }
    }
}

// MARK: - Initial window placement

/// Positions the window in the upper-left corner at a compact size on the very
/// first launch (SwiftUI's `.defaultPosition`/`.defaultSize` are overridden by
/// macOS's window-frame cache). Afterwards the window remembers its own frame.
private struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            guard let window = view.window else { return }
            let key = "didSetInitialWindowFrame"
            guard !UserDefaults.standard.bool(forKey: key) else { return }
            UserDefaults.standard.set(true, forKey: key)

            let size = NSSize(width: 360, height: 420)
            guard let visible = (window.screen ?? NSScreen.main)?.visibleFrame else { return }
            let origin = NSPoint(x: visible.minX, y: visible.maxY - size.height)  // top-left
            window.setFrame(NSRect(origin: origin, size: size), display: true, animate: false)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
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
