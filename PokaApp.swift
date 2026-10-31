import SwiftUI

@main
struct PokaApp: App {
    @State private var vault = VaultService()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(vault)
        }
        #if os(macOS)
        .defaultSize(width: 1100, height: 720)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Note") {
                    NotificationCenter.default.post(name: .pokaCreateNote, object: nil)
                }
                .keyboardShortcut("n", modifiers: [.command])
            }
        }
        #endif
    }
}

extension Notification.Name {
    static let pokaCreateNote = Notification.Name("pokaCreateNote")
}
