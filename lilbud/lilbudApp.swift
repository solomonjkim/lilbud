import SwiftUI

@main
struct LilbudApp: App {
    @State private var store = ChatStore()
    @State private var models = ModelManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .environment(models)
                .environment(RuntimeManager.shared)
                .frame(minWidth: 900, minHeight: 620)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Conversation") { store.createConversation() }
                    .keyboardShortcut("n", modifiers: .command)
            }
        }
    }
}
