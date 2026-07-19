import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Matches the window's toolbar (the header) so footers read as the same
/// surface — forming matching "bookends." Values sampled from the system
/// toolbar in both appearances (material blends can't match it).
func toolbarSurfaceColor(_ scheme: ColorScheme) -> Color {
    scheme == .dark
        ? Color(.sRGB, red: 56.0 / 255, green: 56.0 / 255, blue: 58.0 / 255)
        : Color(.sRGB, red: 239.0 / 255, green: 239.0 / 255, blue: 240.0 / 255)
}

/// The flagship view: a compact, scalable board of playlist cards. Every card is
/// a drop target, so a batch of videos can be filed into one or several
/// playlists at a glance. Cards are reorderable and keyboard-navigable.
struct BoardView: View {
    @Environment(PlaylistStore.self) private var store
    @Environment(\.colorScheme) private var colorScheme

    @State private var namePrompt: NamePrompt?
    @State private var renamingCollection: Collection?
    @FocusState private var listFocused: Bool

    var body: some View {
        @Bindable var store = store

        Group {
            if store.visiblePlaylists.isEmpty {
                emptyState
            } else {
                List(selection: $store.focusedID) {
                    ForEach(store.visiblePlaylists) { playlist in
                        PlaylistCard(playlist: playlist, onNewCollection: { namePrompt = NamePrompt(seed: playlist) })
                            .tag(playlist.id)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets())   // full-bleed row; the card owns its margins
                            .listRowBackground(Color.clear)
                    }
                    .onMove { store.movePlaylists(from: $0, to: $1) }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .contentMargins(.top, 14, for: .scrollContent)   // top gap == inter-card gap (~20pt)
                .focused($listFocused)
                // Up/Down select (the List's own); Right / Return drills into a playlist.
                .onKeyPress(.rightArrow) { openFocused() ? .handled : .ignored }
                .onKeyPress(.return) { openFocused() ? .handled : .ignored }
                // Focus the list on launch and whenever we return from a detail
                // (and relinquish it while a detail is open, so the detail can
                // take focus). Empty selection = no ring at rest.
                .onAppear { listFocused = true }
                .onChange(of: store.navPath) { _, path in
                    if path.isEmpty {
                        // Re-grab focus after the pop settles — setting it
                        // immediately during the transition is dropped, which
                        // left the board with a selection but no keyboard focus.
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(300))
                            listFocused = true
                        }
                    } else {
                        listFocused = false
                    }
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))   // one consistent content color
        .navigationTitle(store.activeCollection?.name ?? "Playlists")
        .toolbar { toolbarContent }
        .safeAreaInset(edge: .bottom) { footer }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            store.receiveDrop(providers, into: nil)
            return true
        }
        .sheet(item: $namePrompt) { prompt in
            CollectionNameSheet(seed: prompt.seed)
        }
        .sheet(item: $renamingCollection) { collection in
            CollectionRenameSheet(collection: collection)
        }
    }

    private func openFocused() -> Bool {
        guard let id = store.focusedID, let playlist = store.playlists.first(where: { $0.id == id }) else { return false }
        store.open(playlist)
        return true
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem {
            collectionMenu
        }
        ToolbarItem {
            Menu {
                Button("New Playlist…") { store.promptNewPlaylist() }
                Button("Add Existing Playlist…") { store.promptAddPlaylist() }
            } label: {
                Label("Add Playlist", systemImage: "plus")
            }
            .help("New or add an existing playlist")
        }
    }

    private var collectionMenu: some View {
        @Bindable var store = store
        return Menu {
            Picker("Collection", selection: $store.activeCollectionID) {
                Text("All Playlists").tag(Collection.ID?.none)
                ForEach(store.collections) { collection in
                    Text(collection.name).tag(Collection.ID?.some(collection.id))
                }
            }
            .pickerStyle(.inline)

            Divider()
            Button("New Collection…") { namePrompt = NamePrompt(seed: nil) }
            if let active = store.activeCollection {
                Button("Rename Collection…") { renamingCollection = active }
                Button("Delete Collection", role: .destructive) { store.deleteCollection(active) }
            }
        } label: {
            Label(store.activeCollection?.name ?? "All Playlists", systemImage: "rectangle.stack")
        }
        .help("Show all playlists or a saved collection")
    }

    // MARK: Footer (pre-sized for two lines so it never grows on wrap)

    private var footer: some View {
        HStack(spacing: 8) {
            if let status = store.status {
                Image(systemName: status.kind.symbol).foregroundStyle(status.kind.tint)
                Text(status.text)
            } else {
                Image(systemName: "tray.and.arrow.down").foregroundStyle(.tertiary)
                Text("Drop videos on a card to add them · drop an .m3u to add a playlist")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.callout)
        .lineLimit(2)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 14)
        .frame(height: 46)
        .background(toolbarSurfaceColor(colorScheme))   // same surface as the toolbar
        .overlay(alignment: .top) { Divider() }         // bookend the header's divider
        .animation(.default, value: store.status)
    }

    // MARK: Empty state

    private var emptyState: some View {
        ContentUnavailableView {
            Label(store.activeCollection == nil ? "No Playlists" : "Empty Collection",
                  systemImage: "film.stack")
        } description: {
            Text(store.activeCollection == nil
                 ? "Drop a .m3u file here, or create one to get started."
                 : "Add playlists to this collection from a card's menu.")
        } actions: {
            if store.activeCollection == nil {
                Button("New Playlist…") { store.promptNewPlaylist() }
                    .buttonStyle(.borderedProminent)
                Button("Add Existing Playlist…") { store.promptAddPlaylist() }
            }
        }
    }
}

private struct NamePrompt: Identifiable {
    let id = UUID()
    var seed: Playlist?
}

// MARK: - Playlist card

private struct PlaylistCard: View {
    @Environment(PlaylistStore.self) private var store
    let playlist: Playlist
    var onNewCollection: () -> Void = {}
    @State private var isTargeted = false
    @State private var isShowingMenu = false

    private var isSelected: Bool { store.focusedID == playlist.id }

    var body: some View {
        // The card owns its margins over a full-bleed backing that hides the
        // List's plain-style selection fill; selection shows as a stroke instead.
        platter
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity)
            // Over-wide backing (clipped by the list) hides the plain-style
            // selection fill, including the slivers at the row's edges.
            .background(Color(nsColor: .windowBackgroundColor).frame(width: 3000))
            .contentShape(Rectangle())
            // The List's native click-selection is unreliable under custom row
            // content, so drive the focus/selection explicitly. Simultaneous
            // gestures so single-click (select) and double-click (open) coexist.
            .simultaneousGesture(TapGesture(count: 1).onEnded { store.focusedID = playlist.id })
            .simultaneousGesture(TapGesture(count: 2).onEnded { store.open(playlist) })
            .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
                store.receiveDrop(providers, into: playlist)
                return true
            }
            // AppKit right-click menu — no full-bleed List highlight. The overlay
            // captures only right-clicks; left-clicks and drags pass through.
            // Feedback: the placard's material lifts while the menu is open.
            .overlay {
                RightClickMenu(
                    buildMenu: buildMenu,
                    onOpen: { isShowingMenu = true },
                    onClose: { isShowingMenu = false }
                )
            }
    }

    // The name is primary; thumbnails collapse (3 → 0) as width shrinks.
    private var platter: some View {
        ViewThatFits(in: .horizontal) {
            row(thumbCount: 3)
            row(thumbCount: 2)
            row(thumbCount: 1)
            row(thumbCount: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(minHeight: 56)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isTargeted ? playlist.accentColor.opacity(0.12) : Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(borderStyle, style: StrokeStyle(lineWidth: borderWidth, dash: isTargeted ? [5] : []))
        )
        .overlay {
            if isShowingMenu {   // lift while the context menu is open
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.07))
            }
        }
        .animation(.easeInOut(duration: 0.12), value: isTargeted)
        .animation(.easeInOut(duration: 0.1), value: isSelected)
        .animation(.easeInOut(duration: 0.12), value: isShowingMenu)
    }

    private var borderStyle: AnyShapeStyle {
        if isTargeted { return AnyShapeStyle(playlist.accentColor) }   // drop target
        if isSelected { return AnyShapeStyle(Color.accentColor) }      // focus ring
        return AnyShapeStyle(.quaternary)                              // idle hairline
    }

    private var borderWidth: CGFloat { (isTargeted || isSelected) ? 2 : 1 }

    private func row(thumbCount: Int) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(playlist.accentColor)
                .frame(width: 5)
                .frame(maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 3) {
                Text(playlist.name)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                subtitle
            }

            Spacer(minLength: 8)

            if thumbCount > 0 {
                ThumbnailPeek(entries: playlist.entries, maxCount: thumbCount)
            }

            Text("\(playlist.entries.count)")
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private var subtitle: some View {
        if isTargeted {
            Label("Drop to add to \(playlist.name)", systemImage: "plus.circle.fill")
                .font(.subheadline)
                .foregroundStyle(playlist.accentColor)
                .lineLimit(1)
        } else if let feedback = playlist.feedback {
            Label(feedback.text, systemImage: feedback.kind.symbol)
                .font(.subheadline)
                .foregroundStyle(feedback.kind.tint)
                .lineLimit(1)
                .transition(.opacity)
        } else {
            Text(infoLine)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var infoLine: String {
        let count = playlist.entries.count
        guard count > 0 else { return "Empty · drop videos to add" }
        var parts = ["\(count) video\(count == 1 ? "" : "s")"]
        if playlist.totalDuration > 0 {
            let h = playlist.totalDuration / 3600
            let m = (playlist.totalDuration % 3600) / 60
            parts.append(h > 0 ? "\(h)h \(m)m" : "\(max(1, m))m")
        }
        if playlist.missingCount > 0 { parts.append("\(playlist.missingCount) missing") }
        return parts.joined(separator: " · ")
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(ClosureMenuItem("Open") { store.open(playlist) })
        menu.addItem(ClosureMenuItem("Play", enabled: !playlist.entries.isEmpty) { store.play(playlist) })
        menu.addItem(ClosureMenuItem("Add Videos…") { store.promptAddVideos(to: playlist) })
        menu.addItem(.separator())

        let addTo = NSMenuItem(title: "Add to Collection", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        for collection in store.collections {
            submenu.addItem(ClosureMenuItem(collection.name, enabled: !store.isPlaylist(playlist, in: collection.id)) {
                store.addToCollection(playlist, collectionID: collection.id)
            })
        }
        if !store.collections.isEmpty { submenu.addItem(.separator()) }
        submenu.addItem(ClosureMenuItem("New Collection…") { onNewCollection() })
        addTo.submenu = submenu
        menu.addItem(addTo)

        if let active = store.activeCollection {
            menu.addItem(ClosureMenuItem("Remove from “\(active.name)”") {
                store.removeFromCollection(playlist, collectionID: active.id)
            })
        }
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("Reveal in Finder") { store.reveal(playlist) })
        menu.addItem(ClosureMenuItem("Remove from List") { store.removePlaylist(playlist) })
        return menu
    }
}

// MARK: - AppKit right-click menu (no List highlight)

/// A menu item that runs a closure. AppKit menu actions fire on the main thread.
private final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void
    init(_ title: String, enabled: Bool = true, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
        isEnabled = enabled
    }
    required init(coder: NSCoder) { fatalError() }
    @objc private func fire() { handler() }
}

/// Transparent overlay that shows an `NSMenu` on right-click (via `menu(for:)`,
/// so there is no SwiftUI/List highlight). It captures *only* right-clicks —
/// left-clicks and drags fall through to the SwiftUI content behind it.
private struct RightClickMenu: NSViewRepresentable {
    var buildMenu: () -> NSMenu
    var onOpen: () -> Void = {}
    var onClose: () -> Void = {}

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.buildMenu = buildMenu
        view.onOpen = onOpen
        view.onClose = onClose
        return view
    }

    func updateNSView(_ nsView: CatcherView, context: Context) {
        nsView.buildMenu = buildMenu
        nsView.onOpen = onOpen
        nsView.onClose = onClose
    }

    final class CatcherView: NSView, NSMenuDelegate {
        var buildMenu: (() -> NSMenu)?
        var onOpen: (() -> Void)?
        var onClose: (() -> Void)?

        override func hitTest(_ point: NSPoint) -> NSView? {
            // Only intercept right-clicks (and control-clicks); everything else
            // passes through to the SwiftUI content below.
            guard let event = NSApp.currentEvent else { return nil }
            switch event.type {
            case .rightMouseDown, .rightMouseUp:
                return self
            case .leftMouseDown where event.modifierFlags.contains(.control):
                return self
            default:
                return nil
            }
        }

        override func menu(for event: NSEvent) -> NSMenu? {
            let menu = buildMenu?() ?? NSMenu()
            menu.delegate = self
            return menu
        }

        func menuWillOpen(_ menu: NSMenu) { onOpen?() }
        func menuDidClose(_ menu: NSMenu) { onClose?() }
    }
}

// MARK: - Thumbnail peek

/// A small stack of the playlist's most recent additions (newest on the right).
private struct ThumbnailPeek: View {
    let entries: [PlaylistEntry]
    var maxCount: Int = 3
    private let size = CGSize(width: 38, height: 22)

    var body: some View {
        HStack(spacing: 3) {
            ForEach(entries.suffix(maxCount)) { entry in
                ThumbnailView(url: entry.fileURL, size: size)
            }
        }
    }
}

// MARK: - Collection sheets

private struct CollectionNameSheet: View {
    @Environment(PlaylistStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let seed: Playlist?
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New Collection").font(.headline)
            Text("A collection groups playlists you want to see together.")
                .font(.caption).foregroundStyle(.secondary)
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit(create)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Create", action: create)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(18)
        .frame(width: 340)
    }

    private func create() {
        let collection = store.createCollection(name: name, with: seed.map { [$0] } ?? [])
        store.activeCollectionID = collection.id
        dismiss()
    }
}

private struct CollectionRenameSheet: View {
    @Environment(PlaylistStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let collection: Collection
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rename Collection").font(.headline)
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit(save)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Rename", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(18)
        .frame(width: 340)
        .onAppear { name = collection.name }
    }

    private func save() {
        store.renameCollection(collection, to: name)
        dismiss()
    }
}
