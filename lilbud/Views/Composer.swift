import SwiftUI

struct Composer: View {
    @Binding var draft: String
    let contextFraction: Double
    let activeTokens: Int
    let contextLimit: Int
    let modelReady: Bool
    let send: () -> Void
    let compact: () -> Void

    private var status: String {
        if contextFraction >= 0.95 { return "Compact before a longer reply" }
        if contextFraction >= 0.85 { return "Consider compacting" }
        return "Context has room"
    }
    private var tint: Color { contextFraction >= 0.85 ? .orange : .mint }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack { Text("Context").font(.caption.weight(.medium)); Spacer(); Text("\(activeTokens.formatted()) / \(contextLimit.formatted()) tokens").font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
                    ProgressView(value: contextFraction).tint(tint)
                }
                Button("Compact", action: compact).buttonStyle(.bordered)
            }
            Text(status).font(.caption).foregroundStyle(contextFraction >= 0.85 ? .orange : .secondary).frame(maxWidth: .infinity, alignment: .leading)
            HStack(alignment: .bottom, spacing: 10) {
                TextField("Message Lilbud", text: $draft, axis: .vertical).textFieldStyle(.roundedBorder).lineLimit(1...5)
                    .onSubmit { send() }
                Button(action: send) { Image(systemName: "arrow.up").fontWeight(.semibold) }.buttonStyle(.borderedProminent).disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !modelReady)
            }
            if !modelReady { Text("Download \(contextLimit == 8_192 ? "Everyday" : "Workhorse") to start chatting.").font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading) }
        }.padding(.horizontal, 28).padding(.vertical, 14)
    }
}

struct CompactionSheet: View {
    @Environment(\.dismiss) private var dismiss
    let conversation: Conversation
    let compact: (CompactionStyle) -> Void
    @State private var style: CompactionStyle = .concise
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Compact this conversation").font(.title2.bold())
            Text("Your full chat remains in local history. Compaction only replaces older messages in the assistant’s active context.").foregroundStyle(.secondary)
            Picker("Summary detail", selection: $style) { ForEach(CompactionStyle.allCases) { Text($0.title).tag($0) } }.pickerStyle(.radioGroup)
            HStack { Spacer(); Button("Cancel") { dismiss() }; Button("Compact") { compact(style); dismiss() }.buttonStyle(.borderedProminent) }
        }.padding(24).frame(width: 460)
    }
}
