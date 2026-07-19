import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Status

/// A transient board-level message (not tied to a single playlist).
struct StatusMessage: Identifiable, Equatable {
    let id = UUID()
    var kind: FeedbackKind
    var text: String
}

// MARK: - Store

@MainActor
@Observable
final class PlaylistStore {
    var playlists: [Playlist] = []
    /// Navigation stack of opened playlists (empty = the board is showing).
    var navPath: [Playlist.ID] = []
    /// Keyboard/mouse focus on the board (drives the selection ring).
    var focusedID: Playlist.ID?
    var status: StatusMessage?
    var isBusy = false

    /// Saved collections and which one is currently filtering the board (nil = All).
    var collections: [Collection] = []
    var activeCollectionID: Collection.ID?

    private let storageKey = "playlistsV2"
    private let legacyBookmarksKey = "playlistBookmarks"
    private let collectionsKey = "collectionsV1"
    private var clearTask: Task<Void, Never>?

    /// The playlist currently opened in the detail view, if any.
    var selectedPlaylist: Playlist? {
        guard let id = navPath.last else { return nil }
        return playlists.first { $0.id == id }
    }

    /// The playlists shown on the board — all of them, or just the active
    /// collection's, in the collection's saved order.
    var visiblePlaylists: [Playlist] {
        guard let id = activeCollectionID,
              let collection = collections.first(where: { $0.id == id }) else {
            return playlists
        }
        let byPath = Dictionary(playlists.map { ($0.stablePath, $0) }, uniquingKeysWith: { a, _ in a })
        return collection.playlistPaths.compactMap { byPath[$0] }
    }

    var activeCollection: Collection? {
        guard let id = activeCollectionID else { return nil }
        return collections.first { $0.id == id }
    }

    /// Whether durations are read from files when adding (Settings toggle).
    private var readsDurations: Bool {
        if UserDefaults.standard.object(forKey: "readDurations") == nil { return true }
        return UserDefaults.standard.bool(forKey: "readDurations")
    }

    init() {
        loadPersisted()
        loadCollections()
    }

    // MARK: Persistence

    private struct Persisted: Codable {
        var bookmark: Data
        var colorIndex: Int
    }

    private func loadPersisted() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let items = try? JSONDecoder().decode([Persisted].self, from: data) {
            for item in items { resolve(item.bookmark, colorIndex: item.colorIndex) }
        } else if let datas = UserDefaults.standard.array(forKey: legacyBookmarksKey) as? [Data] {
            // Migrate the old bookmark-only format, assigning palette colors by order.
            for (index, data) in datas.enumerated() { resolve(data, colorIndex: index) }
            persist()
        }
    }

    private func resolve(_ bookmark: Data, colorIndex: Int) {
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale
        ) else { return }
        let fresh = stale ? (try? url.bookmarkData()) : bookmark
        addPlaylist(url: url, bookmark: fresh ?? bookmark, colorIndex: colorIndex, persist: false)
    }

    private func persist() {
        let items = playlists.compactMap { playlist -> Persisted? in
            guard let bookmark = playlist.bookmark else { return nil }
            return Persisted(bookmark: bookmark, colorIndex: playlist.colorIndex)
        }
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    // MARK: Adding / creating / removing playlists

    /// Least-used palette slot, so new playlists stay visually distinct.
    private func nextColorIndex() -> Int {
        var counts = Array(repeating: 0, count: Playlist.palette.count)
        for playlist in playlists { counts[playlist.colorIndex % counts.count] += 1 }
        return counts.enumerated().min { $0.element < $1.element }?.offset ?? 0
    }

    @discardableResult
    private func addPlaylist(url: URL, bookmark: Data?, colorIndex: Int?, persist shouldPersist: Bool = true) -> Playlist {
        if let existing = playlists.first(where: { $0.url.standardizedFileURL == url.standardizedFileURL }) {
            return existing
        }
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let playlist = Playlist(
            url: url,
            bookmark: bookmark,
            colorIndex: colorIndex ?? nextColorIndex(),
            entries: M3U.parse(text)
        )
        playlists.append(playlist)
        if shouldPersist { persist() }
        return playlist
    }

    @discardableResult
    func addExistingPlaylist(url: URL) -> Playlist {
        let bookmark = try? url.bookmarkData()
        let playlist = addPlaylist(url: url, bookmark: bookmark, colorIndex: nil)
        setStatus(.info, "Added playlist “\(playlist.name)”")
        return playlist
    }

    func removePlaylist(_ playlist: Playlist) {
        playlists.removeAll { $0.id == playlist.id }
        navPath.removeAll { $0 == playlist.id }
        if focusedID == playlist.id { focusedID = nil }
        // Drop it from any collections that referenced it.
        for index in collections.indices {
            collections[index].playlistPaths.removeAll { $0 == playlist.stablePath }
        }
        persist()
        persistCollections()
        setStatus(.info, "Removed “\(playlist.name)” from the list")
    }

    func open(_ playlist: Playlist) {
        focusedID = playlist.id
        navPath.append(playlist.id)
    }

    /// Reorder the board — the active collection's order when one is showing,
    /// otherwise the master playlist order. Both are persisted.
    func movePlaylists(from source: IndexSet, to destination: Int) {
        if let id = activeCollectionID, let index = collections.firstIndex(where: { $0.id == id }) {
            collections[index].playlistPaths.move(fromOffsets: source, toOffset: destination)
            persistCollections()
        } else {
            playlists.move(fromOffsets: source, toOffset: destination)
            persist()
        }
    }

    // MARK: Collections

    private func loadCollections() {
        guard let data = UserDefaults.standard.data(forKey: collectionsKey),
              let items = try? JSONDecoder().decode([Collection].self, from: data) else { return }
        collections = items
    }

    private func persistCollections() {
        if let data = try? JSONEncoder().encode(collections) {
            UserDefaults.standard.set(data, forKey: collectionsKey)
        }
    }

    @discardableResult
    func createCollection(name: String, with playlists: [Playlist] = []) -> Collection {
        var collection = Collection(name: name, playlistPaths: playlists.map(\.stablePath))
        if collection.name.trimmingCharacters(in: .whitespaces).isEmpty { collection.name = "Untitled Collection" }
        collections.append(collection)
        persistCollections()
        setStatus(.info, "Created collection “\(collection.name)”")
        return collection
    }

    func deleteCollection(_ collection: Collection) {
        collections.removeAll { $0.id == collection.id }
        if activeCollectionID == collection.id { activeCollectionID = nil }
        persistCollections()
    }

    func renameCollection(_ collection: Collection, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = collections.firstIndex(where: { $0.id == collection.id }) else { return }
        collections[index].name = trimmed
        persistCollections()
    }

    func addToCollection(_ playlist: Playlist, collectionID: Collection.ID) {
        guard let index = collections.firstIndex(where: { $0.id == collectionID }) else { return }
        if !collections[index].playlistPaths.contains(playlist.stablePath) {
            collections[index].playlistPaths.append(playlist.stablePath)
            persistCollections()
            setStatus(.info, "Added “\(playlist.name)” to “\(collections[index].name)”")
        }
    }

    func removeFromCollection(_ playlist: Playlist, collectionID: Collection.ID) {
        guard let index = collections.firstIndex(where: { $0.id == collectionID }) else { return }
        collections[index].playlistPaths.removeAll { $0 == playlist.stablePath }
        persistCollections()
    }

    func isPlaylist(_ playlist: Playlist, in collectionID: Collection.ID) -> Bool {
        collections.first { $0.id == collectionID }?.playlistPaths.contains(playlist.stablePath) ?? false
    }

    func reveal(_ playlist: Playlist) {
        NSWorkspace.shared.activateFileViewerSelecting([playlist.url])
    }

    /// Open the playlist in the user's default `.m3u` handler (e.g. VLC).
    func play(_ playlist: Playlist) {
        if !NSWorkspace.shared.open(playlist.url) {
            setFeedback(playlist, .error, "No app is set to open .m3u playlists")
        }
    }

    // MARK: Drop routing

    /// Handle a drop of file URLs. `.m3u` files become playlists; video files and
    /// folders are appended to `target`.
    func receiveDrop(_ providers: [NSItemProvider], into target: Playlist?) {
        Task {
            let urls = await Self.loadFileURLs(from: providers)
            let playlistURLs = urls.filter { VideoFile.isPlaylist($0) }
            let mediaURLs = urls.filter { !VideoFile.isPlaylist($0) }

            for url in playlistURLs { addExistingPlaylist(url: url) }

            guard !mediaURLs.isEmpty else { return }
            if let destination = target {
                await appendVideos(from: mediaURLs, to: destination)
            } else if playlistURLs.isEmpty {
                setStatus(.error, "Drop videos onto a playlist card to add them")
            }
        }
    }

    // MARK: Appending videos

    func appendVideos(from urls: [URL], to playlist: Playlist) async {
        let videos = VideoFile.collectVideos(from: urls)
        guard !videos.isEmpty else {
            setFeedback(playlist, .error, "No video files found")
            return
        }

        // Deduplicate against existing entries and within the batch itself.
        var seen = Set(playlist.entries.map { $0.normalizedKey })
        var toAdd: [URL] = []
        var duplicates = 0
        for video in videos {
            let key = PlaylistEntry.normalize(video.path)
            if seen.contains(key) { duplicates += 1; continue }
            seen.insert(key)
            toAdd.append(video)
        }

        guard !toAdd.isEmpty else {
            setFeedback(playlist, .warning, "All \(duplicates) already in playlist")
            return
        }

        // Read durations concurrently, preserving order.
        var durations = Array(repeating: -1, count: toAdd.count)
        if readsDurations {
            isBusy = true
            setFeedback(playlist, .info, "Reading \(toAdd.count) video\(toAdd.count == 1 ? "" : "s")…")
            durations = await withTaskGroup(of: (Int, Int).self) { group in
                for (index, url) in toAdd.enumerated() {
                    group.addTask { (index, await VideoFile.duration(of: url)) }
                }
                var result = Array(repeating: -1, count: toAdd.count)
                for await (index, seconds) in group { result[index] = seconds }
                return result
            }
            isBusy = false
        }

        playlist.checkpoint()
        for (index, url) in toAdd.enumerated() {
            playlist.entries.append(PlaylistEntry(
                duration: durations[index],
                title: url.deletingPathExtension().lastPathComponent,
                extras: [],
                path: url.path
            ))
        }

        do {
            try playlist.save()
        } catch {
            playlist.undo()   // roll back the in-memory change we couldn't persist
            setFeedback(playlist, .error, "Couldn't write to playlist")
            return
        }

        let skipped = duplicates > 0
            ? " · \(duplicates) duplicate\(duplicates == 1 ? "" : "s") skipped"
            : ""
        setFeedback(playlist, .success, "Added \(toAdd.count)\(skipped)")
    }

    // MARK: Editing entries

    func removeEntries(at offsets: IndexSet, from playlist: Playlist) {
        guard !offsets.isEmpty else { return }
        playlist.checkpoint()
        playlist.entries.remove(atOffsets: offsets)
        trySave(playlist, success: "Removed \(offsets.count) item\(offsets.count == 1 ? "" : "s")")
    }

    func removeSelected(_ selection: Set<PlaylistEntry.ID>, from playlist: Playlist) {
        let offsets = IndexSet(playlist.entries.enumerated().compactMap {
            selection.contains($0.element.id) ? $0.offset : nil
        })
        removeEntries(at: offsets, from: playlist)
    }

    func moveEntries(from source: IndexSet, to destination: Int, in playlist: Playlist) {
        playlist.checkpoint()
        playlist.entries.move(fromOffsets: source, toOffset: destination)
        trySave(playlist, success: nil)
    }

    /// Rename an entry's `#EXTINF` title (what VLC displays). No-op if unchanged/blank.
    func renameEntry(_ entry: PlaylistEntry, to newTitle: String, in playlist: Playlist) {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != entry.title,
              let index = playlist.entries.firstIndex(where: { $0.id == entry.id }) else { return }
        playlist.checkpoint()
        playlist.entries[index].title = trimmed
        trySave(playlist, success: "Renamed to “\(trimmed)”")
    }

    func removeEntry(_ entry: PlaylistEntry, from playlist: Playlist) {
        guard let index = playlist.entries.firstIndex(where: { $0.id == entry.id }) else { return }
        removeEntries(at: IndexSet(integer: index), from: playlist)
    }

    func undo(_ playlist: Playlist) {
        guard playlist.undo() else { return }
        trySave(playlist, success: "Undid last change")
    }

    private func trySave(_ playlist: Playlist, success: String?) {
        do {
            try playlist.save()
            if let success { setFeedback(playlist, .success, success) }
        } catch {
            playlist.undo()
            setFeedback(playlist, .error, "Couldn't write to playlist")
        }
    }

    // MARK: File dialogs

    func promptAddPlaylist() {
        let panel = NSOpenPanel()
        panel.title = "Add Playlist"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = playlistContentTypes()
        if panel.runModal() == .OK {
            for url in panel.urls { addExistingPlaylist(url: url) }
        }
    }

    func promptNewPlaylist() {
        let panel = NSSavePanel()
        panel.title = "New Playlist"
        panel.nameFieldStringValue = "New Playlist.m3u"
        panel.allowedContentTypes = playlistContentTypes()
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try "#EXTM3U\n".write(to: url, atomically: true, encoding: .utf8)
                addExistingPlaylist(url: url)
            } catch {
                setStatus(.error, "Couldn't create playlist")
            }
        }
    }

    func promptAddVideos(to playlist: Playlist) {
        let panel = NSOpenPanel()
        panel.title = "Add Videos"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        if panel.runModal() == .OK {
            let urls = panel.urls
            Task { await appendVideos(from: urls, to: playlist) }
        }
    }

    private func playlistContentTypes() -> [UTType] {
        ["m3u", "m3u8"].compactMap { UTType(filenameExtension: $0) }
    }

    // MARK: Feedback / status helpers

    /// A message tied to one playlist — shown on its card and in its status bar.
    func setFeedback(_ playlist: Playlist, _ kind: FeedbackKind, _ text: String) {
        let message = Feedback(kind: kind, text: text)
        playlist.feedback = message
        Task {
            try? await Task.sleep(for: .seconds(5))
            if playlist.feedback?.id == message.id { playlist.feedback = nil }
        }
    }

    private func setStatus(_ kind: FeedbackKind, _ text: String) {
        status = StatusMessage(kind: kind, text: text)
        clearTask?.cancel()
        clearTask = Task {
            try? await Task.sleep(for: .seconds(6))
            if !Task.isCancelled { self.status = nil }
        }
    }

    // MARK: NSItemProvider bridge

    private static func loadFileURLs(from providers: [NSItemProvider]) async -> [URL] {
        await withTaskGroup(of: URL?.self) { group in
            for provider in providers {
                group.addTask { await loadFileURL(provider) }
            }
            var urls: [URL] = []
            for await url in group { if let url { urls.append(url) } }
            return urls
        }
    }

    private static func loadFileURL(_ provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    continuation.resume(returning: url)
                } else if let url = item as? URL {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}

// MARK: - Feedback appearance (view-layer mapping)

extension FeedbackKind {
    var symbol: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error:   return "xmark.octagon.fill"
        case .info:    return "info.circle.fill"
        }
    }
    var tint: Color {
        switch self {
        case .success: return .green
        case .warning: return .orange
        case .error:   return .red
        case .info:    return .secondary
        }
    }
}

extension Playlist {
    /// The palette of stable, distinct accent colors assigned to playlists.
    static let palette: [Color] = [.blue, .purple, .pink, .orange, .green, .teal, .indigo, .red, .cyan, .mint]

    var accentColor: Color { Playlist.palette[colorIndex % Playlist.palette.count] }
}
