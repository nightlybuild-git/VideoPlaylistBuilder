import Foundation
import AVFoundation

// MARK: - Playlist entry

/// One item in an .m3u playlist: an optional `#EXTINF` line, any preserved
/// extra directives (e.g. `#EXTVLCOPT`), and the media path/URL as written.
struct PlaylistEntry: Identifiable, Hashable {
    let id = UUID()
    var duration: Int          // seconds; -1 = unknown
    var title: String
    var extras: [String]       // preserved "#..." lines that belong to this entry
    var path: String           // raw path/URL exactly as stored in the file

    /// A file URL when the path is local; nil for relative or remote (http/…) paths.
    var fileURL: URL? {
        if path.hasPrefix("file://") { return URL(string: path) }
        if path.hasPrefix("/") { return URL(fileURLWithPath: path) }
        return nil
    }

    var fileName: String {
        fileURL?.lastPathComponent ?? (path as NSString).lastPathComponent
    }

    /// A tidied title for display: underscores become spaces and runs of
    /// whitespace collapse. The stored `title` (what VLC reads) is untouched.
    var displayTitle: String {
        let cleaned = title
            .replacingOccurrences(of: "_", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        return cleaned.isEmpty ? title : cleaned
    }

    /// Whether the referenced file is present. Remote/relative entries are
    /// assumed present (we can't cheaply verify them).
    var isMissing: Bool {
        guard let url = fileURL, url.isFileURL else { return false }
        return !FileManager.default.fileExists(atPath: url.path)
    }

    /// Normalized key for duplicate detection — resolves `.`/`..`/symlink noise
    /// so `/Movies/Cars` no longer collides with `/Movies/Cars2`.
    var normalizedKey: String { PlaylistEntry.normalize(path) }

    static func normalize(_ path: String) -> String {
        if path.hasPrefix("file://"), let url = URL(string: path) {
            return url.standardizedFileURL.path
        }
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path).standardizedFileURL.path
        }
        return path
    }

    /// Human-readable duration ("1:32:07", "4:05", or "—" when unknown).
    var displayDuration: String {
        guard duration > 0 else { return "—" }
        let h = duration / 3600
        let m = (duration % 3600) / 60
        let s = duration % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }
}

// MARK: - .m3u parsing / serialization

/// Extended-M3U reader/writer. Unknown `#` directives are preserved so we never
/// silently destroy a user's VLC options on rewrite.
enum M3U {
    static func parse(_ text: String) -> [PlaylistEntry] {
        var entries: [PlaylistEntry] = []
        var pendingDuration = -1
        var pendingTitle: String?
        var pendingExtras: [String] = []

        let lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")

        for raw in lines {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            if trimmed.hasPrefix("#EXTM3U") { continue }

            if trimmed.hasPrefix("#EXTINF:") {
                let rest = String(trimmed.dropFirst("#EXTINF:".count))
                if let comma = rest.firstIndex(of: ",") {
                    let durationField = String(rest[..<comma])
                    pendingDuration = parseDuration(durationField)
                    pendingTitle = String(rest[rest.index(after: comma)...])
                } else {
                    pendingDuration = parseDuration(rest)
                }
                continue
            }

            if trimmed.hasPrefix("#") {
                pendingExtras.append(trimmed)
                continue
            }

            // A media line closes the current entry.
            let title = pendingTitle ?? (trimmed as NSString).lastPathComponent
            entries.append(PlaylistEntry(
                duration: pendingDuration,
                title: title,
                extras: pendingExtras,
                path: trimmed
            ))
            pendingDuration = -1
            pendingTitle = nil
            pendingExtras = []
        }
        return entries
    }

    /// `#EXTINF` duration may carry trailing key="value" attributes; take the number.
    private static func parseDuration(_ field: String) -> Int {
        let numeric = field.trimmingCharacters(in: .whitespaces)
            .prefix { $0 == "-" || $0 == "." || $0.isNumber }
        if let value = Double(numeric) { return Int(value.rounded()) }
        return -1
    }

    static func serialize(_ entries: [PlaylistEntry]) -> String {
        var out = "#EXTM3U\n"
        for entry in entries {
            out += "#EXTINF:\(entry.duration),\(entry.title)\n"
            for extra in entry.extras { out += extra + "\n" }
            out += entry.path + "\n"
        }
        return out
    }
}

// MARK: - Feedback

/// The kind of a transient result message (shown on a card or in the status bar).
/// Color/symbol mapping lives in the view layer so this stays UI-framework-free.
enum FeedbackKind: Equatable {
    case success, warning, error, info
}

/// A short-lived result message tied to a playlist (or the board).
struct Feedback: Equatable, Identifiable {
    let id = UUID()
    var kind: FeedbackKind
    var text: String
}

// MARK: - Collection

/// A saved preset that groups several playlists — "a playlist of playlists."
/// Playlists are referenced by their standardized file path so the link is
/// stable across launches (playlist object IDs are not).
struct Collection: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var playlistPaths: [String] = []
}

// MARK: - Playlist

/// A live playlist backed by a file on disk, with an in-memory undo stack.
@Observable
final class Playlist: Identifiable {
    let id: UUID
    let url: URL
    let bookmark: Data?
    var entries: [PlaylistEntry]

    /// Index into the app's palette — a stable, memorable accent per playlist.
    var colorIndex: Int
    /// Transient result of the last action on this playlist (drop, undo, …).
    var feedback: Feedback?

    private var undoStack: [[PlaylistEntry]] = []
    private let maxUndo = 25

    var name: String { url.deletingPathExtension().lastPathComponent }
    /// Stable identity for cross-launch references (e.g. collections).
    var stablePath: String { url.standardizedFileURL.path }
    var canUndo: Bool { !undoStack.isEmpty }
    var missingCount: Int { entries.reduce(0) { $0 + ($1.isMissing ? 1 : 0) } }

    /// Total known duration in seconds (entries with unknown duration are ignored).
    var totalDuration: Int { entries.reduce(0) { $0 + max(0, $1.duration) } }

    init(id: UUID = UUID(), url: URL, bookmark: Data?, colorIndex: Int = 0, entries: [PlaylistEntry]) {
        self.id = id
        self.url = url
        self.bookmark = bookmark
        self.colorIndex = colorIndex
        self.entries = entries
    }

    func reload() {
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        entries = M3U.parse(text)
    }

    func save() throws {
        try M3U.serialize(entries).write(to: url, atomically: true, encoding: .utf8)
    }

    /// Snapshot current entries before a mutation so it can be undone.
    func checkpoint() {
        undoStack.append(entries)
        if undoStack.count > maxUndo { undoStack.removeFirst() }
    }

    /// Restore the most recent snapshot. Returns true if anything was undone.
    @discardableResult
    func undo() -> Bool {
        guard let previous = undoStack.popLast() else { return false }
        entries = previous
        return true
    }
}

// MARK: - Video files

enum VideoFile {
    static let extensions: Set<String> = [
        "mp4", "mov", "avi", "mkv", "m4v", "wmv", "flv", "webm",
        "mpg", "mpeg", "m2ts", "ts", "ogv", "3gp", "vob", "divx"
    ]

    static func isVideo(_ url: URL) -> Bool {
        extensions.contains(url.pathExtension.lowercased())
    }

    static func isPlaylist(_ url: URL) -> Bool {
        ["m3u", "m3u8"].contains(url.pathExtension.lowercased())
    }

    /// Expand any dropped folders into their contained video files, sorted
    /// naturally so batches land in a predictable order.
    static func collectVideos(from urls: [URL]) -> [URL] {
        let fm = FileManager.default
        var result: [URL] = []
        for url in urls {
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                let enumerator = fm.enumerator(
                    at: url,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                )
                while let file = enumerator?.nextObject() as? URL {
                    if isVideo(file) { result.append(file) }
                }
            } else if isVideo(url) {
                result.append(url)
            }
        }
        return result.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    /// Read a media file's duration in whole seconds; -1 if it can't be read.
    static func duration(of url: URL) async -> Int {
        let asset = AVURLAsset(url: url)
        if let time = try? await asset.load(.duration) {
            let seconds = CMTimeGetSeconds(time)
            if seconds.isFinite && seconds > 0 { return Int(seconds.rounded()) }
        }
        return -1
    }
}
