import SwiftUI
import UniformTypeIdentifiers

struct PlaylistPair: Identifiable {
    let id = UUID()
    var playlistURL: URL?
    var playlistName: String = "Drop .m3u"
    var feedbackMessage: String = ""
    var showFeedback: Bool = false
    var feedbackIcon: String = "film" // Default icon, changes to checkmark/x/warning
    var lastAddedPath: String? // Track last added file for undo
}

struct StatusMessage {
    let rowNumber: Int
    let rowColor: Color
    let type: MessageType
    let fileName: String
    let canUndo: Bool
    
    enum MessageType {
        case success
        case error
        case warning
        case undo
        
        var icon: String {
            switch self {
            case .success: return "checkmark"
            case .error: return "xmark"
            case .warning: return "exclamationmark.triangle"
            case .undo: return "arrow.uturn.backward"
            }
        }
        
        var iconColor: Color {
            switch self {
            case .warning: return .black
            default: return .white
            }
        }
        
        var backgroundColor: Color {
            switch self {
            case .success: return .green
            case .error: return .red
            case .warning: return .yellow
            case .undo: return .blue
            }
        }
    }
}

struct ContentView: View {
    @State private var playlistPairs: [PlaylistPair] = [
        PlaylistPair()
    ]
    @State private var currentStatus: StatusMessage?
    
    var body: some View {
        VStack(spacing: 0) {
            // Scrollable playlist pairs
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(Array(playlistPairs.enumerated()), id: \.element.id) { index, pair in
                        PlaylistRowView(
                            pair: binding(for: index),
                            rowNumber: index + 1,
                            canRemove: playlistPairs.count > 1,
                            rowColor: colorForRow(index),
                            onPlaylistDrop: { providers in
                                handlePlaylistDrop(providers: providers, index: index)
                            },
                            onMovieDrop: { providers in
                                handleMovieDrop(providers: providers, index: index)
                            },
                            onAddRow: {
                                addRow(after: index)
                            },
                            onRemoveRow: {
                                removeRow(at: index)
                            }
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            
            // Status bar at bottom
            if let status = currentStatus {
                HStack(spacing: 8) {
                    // Row indicator
                    HStack(spacing: 4) {
                        Text("Row \(status.rowNumber)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(status.rowColor))
                    
                    // Status icon
                    HStack(spacing: 4) {
                        Image(systemName: status.type.icon)
                            .font(.system(size: 10))
                            .foregroundColor(status.type.iconColor)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(status.type.backgroundColor))
                    
                    // File name message
                    Text(status.fileName)
                        .font(.system(size: 11))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    
                    Spacer()
                    
                    // Undo button
                    if status.canUndo {
                        Button(action: { undoLastAddition(rowIndex: status.rowNumber - 1) }) {
                            Image(systemName: "arrow.uturn.backward")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .background(Capsule().fill(Color(NSColor.quaternaryLabelColor).opacity(0.2)))
                        .help("Undo")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            } else {
                HStack {
                    Text("Ready")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            }
        }
        .frame(width: 450, height: calculateWindowHeight())
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    private func calculateWindowHeight() -> CGFloat {
        let rowHeight: CGFloat = 80
        let rowSpacing: CGFloat = 2
        let verticalPadding: CGFloat = 16 // 8 top + 8 bottom
        let statusBarHeight: CGFloat = 24
        
        let totalRowHeight = CGFloat(playlistPairs.count) * rowHeight
        let totalSpacing = CGFloat(max(0, playlistPairs.count - 1)) * rowSpacing
        
        return totalRowHeight + totalSpacing + verticalPadding + statusBarHeight
    }
    
    private func colorForRow(_ index: Int) -> Color {
        let colors: [Color] = [.orange, .blue, .purple, .green, .red, .pink, .yellow, .cyan]
        return colors[index % colors.count]
    }
    
    private func binding(for index: Int) -> Binding<PlaylistPair> {
        Binding(
            get: { playlistPairs[index] },
            set: { playlistPairs[index] = $0 }
        )
    }
    
    private func addRow(after index: Int) {
        playlistPairs.insert(PlaylistPair(), at: index + 1)
    }
    
    private func removeRow(at index: Int) {
        guard playlistPairs.count > 1 else { return }
        playlistPairs.remove(at: index)
    }
    
    private func handlePlaylistDrop(providers: [NSItemProvider], index: Int) -> Bool {
        guard let provider = providers.first else { return false }
        
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { (item, error) in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil),
                  url.pathExtension.lowercased() == "m3u" else {
                DispatchQueue.main.async {
                    showFeedback(
                        type: .error,
                        fileName: "Only .m3u files allowed",
                        at: index,
                        canUndo: false
                    )
                }
                return
            }
            
            DispatchQueue.main.async {
                playlistPairs[index].playlistURL = url
                playlistPairs[index].playlistName = url.lastPathComponent
                showFeedback(
                    type: .success,
                    fileName: "Loaded \(url.lastPathComponent)",
                    at: index,
                    canUndo: false
                )
            }
        }
        
        return true
    }
    
    private func handleMovieDrop(providers: [NSItemProvider], index: Int) -> Bool {
        guard !providers.isEmpty else { return false }
        
        guard let playlistURL = playlistPairs[index].playlistURL else {
            DispatchQueue.main.async {
                showFeedback(
                    type: .error,
                    fileName: "Load playlist first",
                    at: index,
                    canUndo: false
                )
            }
            return false
        }
        
        // Process all providers
        let group = DispatchGroup()
        var movieURLs: [URL] = []
        
        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { (item, error) in
                defer { group.leave() }
                
                guard let data = item as? Data,
                      let movieURL = URL(dataRepresentation: data, relativeTo: nil) else {
                    return
                }
                
                // Check if it's a video file
                let videoExtensions = ["mp4", "mov", "avi", "mkv", "m4v", "wmv", "flv", "webm", "mpg", "mpeg"]
                if videoExtensions.contains(movieURL.pathExtension.lowercased()) {
                    movieURLs.append(movieURL)
                }
            }
        }
        
        group.notify(queue: .main) {
            if movieURLs.isEmpty {
                showFeedback(
                    type: .error,
                    fileName: "No valid video files",
                    at: index,
                    canUndo: false
                )
            } else {
                addMultipleToPlaylist(movieURLs: movieURLs, playlistURL: playlistURL, index: index)
            }
        }
        
        return true
    }
    
    private func addToPlaylist(movieURL: URL, playlistURL: URL, index: Int) {
        do {
            // Read existing playlist
            var playlistContent = try String(contentsOf: playlistURL, encoding: .utf8)
            
            // Check for duplicates
            let moviePath = movieURL.path
            if playlistContent.contains(moviePath) {
                DispatchQueue.main.async {
                    let fileName = movieURL.lastPathComponent
                    showFeedback(
                        type: .warning,
                        fileName: "\(fileName) already in playlist",
                        at: index,
                        canUndo: false
                    )
                }
                return
            }
            
            // Prepare the entry
            let fileName = movieURL.deletingPathExtension().lastPathComponent
            let duration = "-1" // Unknown duration
            
            // Add EXTINF line and file path
            let newEntry = "\n#EXTINF:\(duration),\(fileName)\n\(moviePath)"
            
            // Ensure playlist has proper header
            if !playlistContent.hasPrefix("#EXTM3U") {
                playlistContent = "#EXTM3U\n" + playlistContent
            }
            
            // Append the new entry
            playlistContent += newEntry
            
            // Write back to file
            try playlistContent.write(to: playlistURL, atomically: true, encoding: .utf8)
            
            DispatchQueue.main.async {
                // Track for undo
                playlistPairs[index].lastAddedPath = moviePath
                
                let displayName = movieURL.lastPathComponent
                showFeedback(
                    type: .success,
                    fileName: "Added \(displayName)",
                    at: index,
                    canUndo: true
                )
            }
            
        } catch {
            DispatchQueue.main.async {
                showFeedback(
                    type: .error,
                    fileName: "Failed to write to playlist",
                    at: index,
                    canUndo: false
                )
            }
        }
    }
    
    private func addMultipleToPlaylist(movieURLs: [URL], playlistURL: URL, index: Int) {
        do {
            // Read existing playlist
            var playlistContent = try String(contentsOf: playlistURL, encoding: .utf8)
            
            // Ensure playlist has proper header
            if !playlistContent.hasPrefix("#EXTM3U") {
                playlistContent = "#EXTM3U\n" + playlistContent
            }
            
            var addedCount = 0
            var duplicateCount = 0
            var firstAddedName = ""
            var lastAddedPath: String?
            
            for movieURL in movieURLs {
                let moviePath = movieURL.path
                
                // Check for duplicates
                if playlistContent.contains(moviePath) {
                    duplicateCount += 1
                    continue
                }
                
                // Prepare the entry
                let fileName = movieURL.deletingPathExtension().lastPathComponent
                let duration = "-1"
                
                // Add EXTINF line and file path
                let newEntry = "\n#EXTINF:\(duration),\(fileName)\n\(moviePath)"
                playlistContent += newEntry
                
                if addedCount == 0 {
                    firstAddedName = movieURL.lastPathComponent
                }
                lastAddedPath = moviePath
                addedCount += 1
            }
            
            // Write back to file
            if addedCount > 0 {
                try playlistContent.write(to: playlistURL, atomically: true, encoding: .utf8)
            }
            
            DispatchQueue.main.async {
                // Determine feedback message
                if addedCount == 0 {
                    showFeedback(
                        type: .warning,
                        fileName: "All \(duplicateCount) file\(duplicateCount == 1 ? "" : "s") already in playlist",
                        at: index,
                        canUndo: false
                    )
                } else if addedCount == 1 {
                    // Track for undo (single file case)
                    playlistPairs[index].lastAddedPath = lastAddedPath
                    showFeedback(
                        type: duplicateCount > 0 ? .warning : .success,
                        fileName: duplicateCount > 0 ? "Added \(firstAddedName), \(duplicateCount) duplicate\(duplicateCount == 1 ? "" : "s") skipped" : "Added \(firstAddedName)",
                        at: index,
                        canUndo: true
                    )
                } else {
                    // Multiple files added - can't undo
                    showFeedback(
                        type: duplicateCount > 0 ? .warning : .success,
                        fileName: duplicateCount > 0 ? "Added \(addedCount) files, \(duplicateCount) duplicate\(duplicateCount == 1 ? "" : "s") skipped" : "Added \(addedCount) files",
                        at: index,
                        canUndo: false
                    )
                }
            }
            
        } catch {
            DispatchQueue.main.async {
                showFeedback(
                    type: .error,
                    fileName: "Failed to write to playlist",
                    at: index,
                    canUndo: false
                )
            }
        }
    }
    
    private func showFeedback(type: StatusMessage.MessageType, fileName: String, at index: Int, canUndo: Bool) {
        currentStatus = StatusMessage(
            rowNumber: index + 1,
            rowColor: colorForRow(index),
            type: type,
            fileName: fileName,
            canUndo: canUndo
        )
        
        // Change icon based on feedback type
        switch type {
        case .error:
            playlistPairs[index].feedbackIcon = "xmark.circle"
        case .warning:
            playlistPairs[index].feedbackIcon = "exclamationmark.triangle"
        case .success, .undo:
            playlistPairs[index].feedbackIcon = "checkmark.circle"
        }
        
        // Reset icon after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            playlistPairs[index].feedbackIcon = "film"
        }
    }
    
    private func undoLastAddition(rowIndex: Int) {
        guard let playlistURL = playlistPairs[rowIndex].playlistURL,
              let lastPath = playlistPairs[rowIndex].lastAddedPath else {
            return
        }
        
        do {
            // Read playlist
            var playlistContent = try String(contentsOf: playlistURL, encoding: .utf8)
            
            // Find and remove the entry
            let lines = playlistContent.components(separatedBy: "\n")
            var newLines: [String] = []
            var skipNext = false
            
            for (_, line) in lines.enumerated() {
                if skipNext {
                    skipNext = false
                    continue
                }
                
                if line == lastPath {
                    // Skip this line and the EXTINF line before it
                    if !newLines.isEmpty && newLines.last?.hasPrefix("#EXTINF") == true {
                        newLines.removeLast()
                    }
                    continue
                }
                
                newLines.append(line)
            }
            
            playlistContent = newLines.joined(separator: "\n")
            try playlistContent.write(to: playlistURL, atomically: true, encoding: .utf8)
            
            let fileName = URL(fileURLWithPath: lastPath).lastPathComponent
            showFeedback(
                type: .undo,
                fileName: "Undid addition of \(fileName)",
                at: rowIndex,
                canUndo: false
            )
            
            playlistPairs[rowIndex].lastAddedPath = nil
            
        } catch {
            showFeedback(
                type: .error,
                fileName: "Failed to undo",
                at: rowIndex,
                canUndo: false
            )
        }
    }
}

struct PlaylistRowView: View {
    @Binding var pair: PlaylistPair
    let rowNumber: Int
    let canRemove: Bool
    let rowColor: Color
    let onPlaylistDrop: ([NSItemProvider]) -> Bool
    let onMovieDrop: ([NSItemProvider]) -> Bool
    let onAddRow: () -> Void
    let onRemoveRow: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Row number
            Text("\(rowNumber)")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 20)
            
            // Playlist drop zone
            CompactDropZoneView(
                title: pair.playlistName,
                icon: pair.playlistURL != nil ? "music.note.list" : "doc",
                isPlaylist: true,
                borderColor: rowColor
            )
            .frame(height: 80)
            .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                onPlaylistDrop(providers)
            }
            
            // Movie drop zone with dynamic icon
            CompactDropZoneView(
                title: "Drop movie",
                icon: pair.feedbackIcon,
                isPlaylist: false,
                borderColor: rowColor
            )
            .frame(height: 80)
            .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                onMovieDrop(providers)
            }
            
            // Control buttons
            VStack(spacing: 6) {
                Button(action: onAddRow) {
                    Image(systemName: "plus")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                .help("Add row below")
                
                if canRemove {
                    Button(action: onRemoveRow) {
                        Image(systemName: "minus")
                            .font(.system(size: 16))
                            .foregroundColor(.secondary)
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("Remove this row")
                }
            }
            .frame(width: 30)
        }
    }
}

struct CompactDropZoneView: View {
    let title: String
    let icon: String
    let isPlaylist: Bool
    let borderColor: Color
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(.secondary)
                .frame(width: 30)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(borderColor, style: StrokeStyle(lineWidth: 1.5, dash: [4]))
                .opacity(0.6)
        )
    }
}

#Preview {
    ContentView()
}
