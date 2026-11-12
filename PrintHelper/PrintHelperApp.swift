import SwiftUI

@main
struct PrintHelperApp: App {
    var body: some Scene {
        WindowGroup {
            #if os(macOS)
            MacEditorView()
                .frame(minWidth: 760, minHeight: 600)
            #else
            IOSEditorView()
            #endif
        }
        #if os(macOS)
        .defaultSize(width: 900, height: 800)
        .commands { DocumentCommands() }
        #endif
    }
}