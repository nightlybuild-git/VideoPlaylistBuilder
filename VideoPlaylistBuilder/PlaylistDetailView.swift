import SwiftUI
import AppKit
import UniformTypeIdentifiers
import QuickLook

struct PlaylistDetailView: View {
    @Environment(PlaylistStore.self) private var store
    @Environment(\.colorScheme) private var colorScheme
    let playlist: Playlist

    @State private var selection = Set<PlaylistEntry.ID>()
    @State private var isTargeted = false
    @State private var renamingEntry: PlaylistEntry?
    @State private var previewURL: URL?
    @FocusState private var listFocused: Bool

    var body: some View {
        let busy = store.isBusy

        Group {
            if playlist.entries.isEmpty {
                emptyState
            } else {
                entryList
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))   // match the board's content color
        .navigationTitle(playlist.name)
        .navigationSubtitle(subtitle)
        .toolbar { toolbarContent }
        .safeAreaInset(edge: .bottom) { statusBar }
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            store.receiveDrop(providers, into: playlist)
            return true
        }
        .overlay { dropHighlight }
        .overlay { if busy { busyOverlay } }
        .sheet(item: $renamingEntry) { entry in
            RenameSheet(entry: entry, playlist: playlist)
        }
        .quickLookPreview($previewURL)
        .defaultFocus($listFocused, true)   // focus the list when the detail appears
        .onAppear {
            // Belt-and-suspenders: grab focus once the push settles, so arrow
            // keys drive the entries immediately after drilling in.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(350))
                listFocused = true
            }
        }
        // Up/Down select entries; Space = Quick Look; Left / ⌘↑ = drill out.
        .onKeyPress(.space) { previewSelection() ? .handled : .ignored }
        .onKeyPress(.leftArrow) { goBack() }
        .onKeyPress(keys: [.upArrow]) { press in
            press.modifiers.contains(.command) ? goBack() : .ignored
        }
    }

    private func goBack() -> KeyPress.Result {
        guard !store.navPath.isEmpty else { return .ignored }
        store.navPath.removeLast()
        return .handled
    }

    private func previewSelection() -> Bool {
        guard let id = selection.first,
              let entry = playlist.entries.first(where: { $0.id == id }),
              let url = entry.fileURL, url.isFileURL, !entry.isMissing else { return false }
        previewURL = url
        return true
    }

    // MARK: Entry list

    private var entryList: some View {
        List(selection: $selection) {
            ForEach(playlist.entries) { entry in
                EntryRow(entry: entry, playlist: playlist,
                         onRename: { renamingEntry = entry },
                         onQuickLook: { previewURL = entry.fileURL })
                    .tag(entry.id)
                    .contextMenu { rowMenu(for: entry) }
            }
            .onMove { source, destination in
                store.moveEntries(from: source, to: destination, in: playlist)
            }
            .onDelete { offsets in
                store.removeEntries(at: offsets, from: playlist)
            }
        }
        .onDeleteCommand {
            store.removeSelected(selection, from: playlist)
            selection.removeAll()
        }
        .scrollContentBackground(.hidden)   // show the shared content color, like the board
        .focused($listFocused)
    }

    @ViewBuilder
    private func rowMenu(for entry: PlaylistEntry) -> some View {
        if let url = entry.fileURL, !entry.isMissing {
            Button("Quick Look") { previewURL = url }
            Button("Play") { NSWorkspace.shared.open(url) }
        }
        Button("Rename…") { renamingEntry = entry }
        if let url = entry.fileURL {
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        }
        Divider()
        Button("Remove", role: .destructive) {
            store.removeEntry(entry, from: playlist)
        }
    }

    // MARK: Empty state

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Empty Playlist", systemImage: "film.stack")
        } description: {
            Text("Drop video files or folders here to add them to “\(playlist.name)”.")
        } actions: {
            Button("Add Videos…") { store.promptAddVideos(to: playlist) }
        }
        // Fill the window (so the footer stays pinned to the bottom, like the
        // non-empty view) and stay focusable for keyboard-back — but with no
        // visible focus ring around the group.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .focusable()
        .focusEffectDisabled()
        .focused($listFocused)
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            Button {
                store.play(playlist)
            } label: {
                Label("Play", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .help("Open this playlist in your default player")
            .disabled(playlist.entries.isEmpty)

            Button {
                store.promptAddVideos(to: playlist)
            } label: {
                Label("Add Videos", systemImage: "plus")
            }
            .labelStyle(.titleAndIcon)
            .help("Add videos to this playlist")

            Button {
                store.undo(playlist)
            } label: {
                Label("Undo", systemImage: "arrow.uturn.backward")
            }
            .help("Undo last change")
            .disabled(!playlist.canUndo)

            Button {
                store.reveal(playlist)
            } label: {
                Label("Reveal in Finder", systemImage: "folder")
            }
            .help("Reveal playlist file in Finder")
        }
    }

    // MARK: Status bar

    private var statusBar: some View {
        ZStack {
            // Centered message (mirrors the board footer).
            Group {
                if let feedback = playlist.feedback {
                    Text(feedback.text).foregroundStyle(feedback.kind.tint)
                } else {
                    Text("Drag videos or folders here to add them")
                        .foregroundStyle(.secondary)
                }
            }
            .lineLimit(2)
            .multilineTextAlignment(.center)

            // Undo floats at the trailing edge without shifting the centered text.
            if playlist.feedback != nil && playlist.canUndo {
                HStack {
                    Spacer()
                    Button("Undo") { store.undo(playlist) }
                        .buttonStyle(.link)
                }
            }
        }
        .font(.callout)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 14)
        .frame(height: 46)
        .background(toolbarSurfaceColor(colorScheme))   // same surface as the toolbar
        .overlay(alignment: .top) { Divider() }         // bookend the header's divider
        .animation(.default, value: playlist.feedback)
    }

    // MARK: Overlays

    @ViewBuilder
    private var dropHighlight: some View {
        if isTargeted {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(playlist.accentColor, lineWidth: 2)
                .padding(6)
                .allowsHitTesting(false)
                .transition(.opacity)
        }
    }

    private var busyOverlay: some View {
        VStack(spacing: 8) {
            ProgressView()
            Text("Reading videos…")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .allowsHitTesting(false)
    }

    // MARK: Subtitle

    private var subtitle: String {
        let count = playlist.entries.count
        var parts = ["\(count) item\(count == 1 ? "" : "s")"]
        if playlist.totalDuration > 0 {
            parts.append(formattedTotal(playlist.totalDuration))
        }
        if playlist.missingCount > 0 {
            parts.append("\(playlist.missingCount) missing")
        }
        return parts.joined(separator: " · ")
    }

    private func formattedTotal(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m" }
        return "\(seconds)s"
    }
}

// MARK: - Entry row

struct EntryRow: View {
    @Environment(PlaylistStore.self) private var store
    let entry: PlaylistEntry
    let playlist: Playlist
    var onRename: () -> Void = {}
    var onQuickLook: () -> Void = {}

    @State private var metadata: MediaMetadata?
    @State private var isHovering = false

    private let thumbSize = CGSize(width: 46, height: 28)

    var body: some View {
        HStack(spacing: 10) {
            if entry.isMissing {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.orange.opacity(0.12))
                    .frame(width: thumbSize.width, height: thumbSize.height)
                    .overlay {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.orange)
                    }
            } else {
                ThumbnailView(url: entry.fileURL, size: thumbSize)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(entry.displayTitle)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(secondaryText)
                    .font(.caption)
                    .foregroundStyle(entry.isMissing ? Color.orange : Color.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            if isHovering {
                hoverActions
            } else {
                Text(entry.displayDuration)
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
        .onHover { isHovering = $0 }
        .task(id: entry.fileURL) {
            metadata = nil
            guard !entry.isMissing, let url = entry.fileURL, url.isFileURL else { return }
            metadata = await MediaMetadataProvider.shared.metadata(for: url)
        }
    }

    private var hoverActions: some View {
        HStack(spacing: 2) {
            if let url = entry.fileURL, !entry.isMissing {
                iconButton("eye", "Quick Look") { onQuickLook() }
                iconButton("play.fill", "Play") { NSWorkspace.shared.open(url) }
            }
            iconButton("pencil", "Rename") { onRename() }
            iconButton("trash", "Remove") { store.removeEntry(entry, from: playlist) }
        }
    }

    private func iconButton(_ symbol: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.callout)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .help(help)
    }

    /// Secondary line: distinct metadata (folder · resolution · format · size),
    /// never a repeat of the title.
    private var secondaryText: String {
        if entry.isMissing { return "Missing · \(entry.fileName)" }
        guard let url = entry.fileURL, url.isFileURL else { return entry.path }

        var parts: [String] = []
        let folder = url.deletingLastPathComponent().lastPathComponent
        if !folder.isEmpty { parts.append(folder) }
        if let resolution = metadata?.resolutionLabel { parts.append(resolution) }
        let ext = url.pathExtension.uppercased()
        if !ext.isEmpty { parts.append(ext) }
        if let size = metadata?.sizeLabel { parts.append(size) }
        return parts.isEmpty ? entry.fileName : parts.joined(separator: " · ")
    }
}

// MARK: - Rename sheet

private struct RenameSheet: View {
    @Environment(PlaylistStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let entry: PlaylistEntry
    let playlist: Playlist

    @State private var title: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rename Item")
                .font(.headline)
            Text("This changes the title VLC shows — the file isn't renamed.")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("Title", text: $title)
                .textFieldStyle(.roundedBorder)
                .onSubmit(save)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Rename", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(18)
        .frame(width: 360)
        .onAppear { title = entry.title }
    }

    private func save() {
        store.renameEntry(entry, to: title, in: playlist)
        dismiss()
    }
}
