import SwiftUI
import AVFoundation
import QuickLookThumbnailing

// MARK: - Thumbnails

/// Generates and caches poster-frame thumbnails for video files via QuickLook.
@MainActor
final class ThumbnailLoader {
    static let shared = ThumbnailLoader()
    private let cache = NSCache<NSString, NSImage>()

    func thumbnail(for url: URL, size: CGSize, scale: CGFloat) async -> NSImage? {
        let key = Self.key(url, size)
        if let image = cache.object(forKey: key) { return image }

        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: size,
            scale: scale,
            representationTypes: .thumbnail
        )
        guard let rep = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) else {
            return nil
        }
        let image = rep.nsImage
        cache.setObject(image, forKey: key)
        return image
    }

    private static func key(_ url: URL, _ size: CGSize) -> NSString {
        "\(url.path)|\(Int(size.width))x\(Int(size.height))" as NSString
    }
}

/// A rounded video poster with a film-glyph placeholder while it loads.
struct ThumbnailView: View {
    let url: URL?
    var size = CGSize(width: 46, height: 28)
    @State private var image: NSImage?

    var body: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(Color.secondary.opacity(0.12))
            .frame(width: size.width, height: size.height)
            .overlay {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "film")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
            )
            .task(id: url) {
                image = nil
                guard let url, url.isFileURL,
                      FileManager.default.fileExists(atPath: url.path) else { return }
                let scale = NSScreen.main?.backingScaleFactor ?? 2
                image = await ThumbnailLoader.shared.thumbnail(for: url, size: size, scale: scale)
            }
    }
}

// MARK: - Media metadata (resolution + size)

struct MediaMetadata: Equatable {
    var resolutionLabel: String?
    var sizeLabel: String?
}

/// Reads and caches a video's display resolution and file size for the row's
/// secondary line — so it shows something other than the filename again.
@MainActor
final class MediaMetadataProvider {
    static let shared = MediaMetadataProvider()
    private var cache: [String: MediaMetadata] = [:]

    func metadata(for url: URL) async -> MediaMetadata {
        if let meta = cache[url.path] { return meta }

        var meta = MediaMetadata()
        if let values = try? url.resourceValues(forKeys: [.fileSizeKey]), let bytes = values.fileSize {
            meta.sizeLabel = ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
        }

        let asset = AVURLAsset(url: url)
        if let track = try? await asset.loadTracks(withMediaType: .video).first,
           let naturalSize = try? await track.load(.naturalSize),
           let transform = try? await track.load(.preferredTransform) {
            let applied = naturalSize.applying(transform)
            meta.resolutionLabel = Self.resolutionLabel(
                width: Int(abs(applied.width)),
                height: Int(abs(applied.height))
            )
        }

        cache[url.path] = meta
        return meta
    }

    private static func resolutionLabel(width: Int, height: Int) -> String? {
        guard height > 0 else { return nil }
        switch height {
        case 2160...:      return "4K"
        case 1440..<2160:  return "1440p"
        case 1080..<1440:  return "1080p"
        case 720..<1080:   return "720p"
        case 480..<720:    return "480p"
        default:           return "\(width)×\(height)"
        }
    }
}
