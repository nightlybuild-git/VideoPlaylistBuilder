# Video Playlist Builder

A native macOS app for building and maintaining VLC `.m3u` playlists. Your
playlists live on a compact **drop board** — file new videos into one or several
playlists by dragging them onto the cards, then click a card to see and edit
what's inside.

## Features

- **Drop board** — every playlist is a card you can drop videos or folders onto; file into one or many playlists at a glance, with no selecting or switching first
- **Glanceable identity** — each playlist has a stable **accent color** and a **thumbnail peek** of its most recent additions, so targets are easy to recognize and hit
- **Inline feedback** — after a drop, the card shows the result right there (`Added 3 · 1 duplicate skipped`)
- **Reorderable & keyboard-navigable** — drag cards to reorder; ↑/↓ navigate, → drills into a playlist, ← or ⌘↑ drills back out (Finder-style). Navigation starts on the first arrow press or click — no focus ring until then.
- **Collections** — save presets that group several playlists ("a playlist of playlists") and filter the board to one collection at a time
- **Adaptive layout** — the window narrows down to a compact strip; the playlist name always wins and thumbnails hide progressively to avoid it
- **Scales to the job** — the window stays small for a few playlists and scrolls when you have many
- **Quick Look** — press Space (or the eye button) on a playlist entry to preview the video; Play still opens the whole playlist in VLC
- **Persistent** — playlists you add stay across launches (stored as file bookmarks, so they survive moves and renames)
- **See & edit inside** — click a card to open its entries with a **video thumbnail**, cleaned title, duration, and metadata (folder · resolution · format · size); reorder (drag), remove (Delete / context menu), with multi‑level Undo
- **Play** — open a whole playlist in your default `.m3u` player (e.g. VLC), or play any entry from its context menu
- **Folder & batch drops** — dropping a folder recurses into it and adds every video found
- **Real durations** — durations are read from the video files (AVFoundation) so entries use a proper `#EXTINF`
- **Smart duplicate detection** — paths are normalized before comparison, so `/Movies/Cars` no longer collides with `/Movies/Cars2`
- **Non‑destructive rewrites** — unknown directives (e.g. `#EXTVLCOPT`) are preserved when a playlist is saved
- **Missing‑file awareness** — entries whose file is gone are flagged, with a count in the title bar
- **Native throughout** — `NavigationStack` board + detail, unified toolbar, menu‑bar commands, Settings, count badges, SF Symbols, and full Light/Dark support

## How to Build

1. Open `VideoPlaylistBuilder.xcodeproj` in Xcode
2. Select your development team in the project settings (if required)
3. Build and run the project (⌘R)

## How to Use

1. **Add a playlist** — drop a `.m3u` file onto the board, or use the **+** menu in the toolbar (*New Playlist…* / *Add Existing Playlist…*)
2. **File videos** — drag video files or folders onto any playlist card. The card highlights in its color and confirms the result inline. Durations are read automatically and duplicates are skipped.
3. **See & edit** — click a card to open it: drag rows to reorder, press Delete (or right‑click → Remove) to remove, and ⌘Z to undo the last change
4. **Find & play** — right‑click a card to *Play*, *Add Videos…*, or *Reveal in Finder*; inside a playlist, right‑click an entry to play or reveal it

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| ↑ / ↓ | Navigate playlists (board) or entries (inside a playlist) |
| → / Return | Drill into the selected playlist |
| ← / ⌘↑ | Drill out, back to the board |
| Space | Quick Look the selected entry |
| ⌘N | New Playlist… |
| ⇧⌘O | Add Existing Playlist… |
| ⇧⌘A | Add Videos… |
| ⌘↩ | Play (open playlist in default player) |
| ⌘R | Reveal playlist in Finder |
| ⌘Z | Undo last change |

## Requirements

- macOS 14.0 or later
- Xcode 15.0 or later (for building)

## .m3u Format

The app reads and writes the extended M3U format:
```
#EXTM3U
#EXTINF:212,Big Buck Bunny
/path/to/Big Buck Bunny.mp4
```

Duration is written in whole seconds (or `-1` when it can't be read). Any extra
directives already present in a playlist are preserved on save.

## Settings

- **Read durations from video files when adding** — on by default. Turn it off for faster adds when you don't need durations.

## License

Released under the [MIT License](LICENSE).
