# Video Playlist Builder

A macOS application for managing multiple VLC .m3u playlist files.

## Features

- **Dynamic Rows**: Start with one playlist row, add more as needed
- **Add/Remove Controls**: Plus and minus buttons to manage rows
- **Clean Interface**: Minimal design without unnecessary labels
- **Playlist Drop Zones**: Left side accepts VLC .m3u playlist files
- **Movie Drop Zones**: Right side accepts movie files (mp4, mov, avi, mkv, m4v, wmv, flv, webm, mpg, mpeg)
- **Duplicate Detection**: Automatically checks for duplicates before adding
- **Per-Row Feedback**: Each row shows its own success/error messages
- **Dynamic Playlist Switching**: Change any playlist by dropping a new .m3u file on its row
- **Auto-Resizing Window**: Window grows and shrinks based on the number of rows

## How to Build

1. Open `VideoPlaylistBuilder.xcodeproj` in Xcode
2. Select your development team in the project settings (if required)
3. Build and run the project (⌘R)

## How to Use

1. **Load a Playlist**: Drag and drop a .m3u file onto the left drop zone
   - The filename will appear to confirm it's loaded
   
2. **Add Movies**: Drag and drop movie files onto the right drop zone of the corresponding row
   - The app will check for duplicates in that specific playlist
   - If the file isn't already in the playlist, it will be added
   - A confirmation message will appear below the row

3. **Add More Rows**: Click the **+** button to add another playlist row below the current one

4. **Remove Rows**: Click the **−** button to remove a row (always keeps at least one row)

5. **Manage Multiple Playlists**: Add as many rows as you need to update multiple playlists

## Interface

- **Row Numbers**: Each row is numbered for easy reference
- **Plus Button**: Adds a new row immediately below the current row
- **Minus Button**: Removes the current row (disabled when only one row exists)
- **Compact Drop Zones**: Horizontal layout with icons
- **Auto-Growing**: Window automatically resizes to fit your rows

## Requirements

- macOS 13.0 or later
- Xcode 15.0 or later (for building)

## .m3u Format

The application follows the extended M3U format:
```
#EXTM3U
#EXTINF:-1,Movie Name
/path/to/movie.mp4
```

## Notes

- The app preserves the full file path in the playlist
- Unknown duration (-1) is used for added files
- The playlist file is automatically created with the #EXTM3U header if missing
- Each row operates independently
- You can add as many rows as you need

## License

Released under the [MIT License](LICENSE).
