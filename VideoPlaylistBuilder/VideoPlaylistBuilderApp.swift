import SwiftUI

@main
struct VideoPlaylistBuilderApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Video Playlist Builder") {
                    NSApp.orderFrontStandardAboutPanel()
                }
            }
        }
    }
}
