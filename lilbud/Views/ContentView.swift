import SwiftUI

struct ContentView: View {
    @Environment(ChatStore.self) private var store
    var body: some View {
        NavigationSplitView {
            SidebarView().navigationSplitViewColumnWidth(min: 230, ideal: 270)
        } detail: {
            if let conversation = store.selectedConversation { ChatView(conversation: conversation).id(conversation.id) }
        }
        .tint(.mint)
    }
}

private struct SidebarView: View {
    @Environment(ChatStore.self) private var store
    var body: some View {
        List(selection: Binding(get: { store.selectedConversationID }, set: { store.selectedConversationID = $0 })) {
            Section("Conversations") {
                ForEach(store.conversations) { chat in
                    Label(chat.title, systemImage: chat.tier == .everyday ? "leaf" : "bolt")
                        .lineLimit(1).tag(chat.id)
                        .contextMenu { Button("Delete", role: .destructive) { store.delete(chat.id) } }
                }
            }
        }
        .navigationTitle("Lilbud")
        .toolbar { ToolbarItem(placement: .primaryAction) { Button(action: store.createConversation) { Image(systemName: "square.and.pencil") }.help("New Conversation") } }
    }
}
