import SwiftUI

/// Switches which conversation the watch mirrors.
///
/// The phone caps the list, so the view says when it was cut rather than
/// implying these are all the threads there are.
struct ThreadPickerView: View {
  @EnvironmentObject private var client: WatchSessionClient
  @Environment(\.dismiss) private var dismiss

  let conversations: [WatchConversation]
  let currentId: String?
  let truncated: Bool

  var body: some View {
    List {
      ForEach(conversations) { conversation in
        Button {
          client.selectConversation(id: conversation.id)
          dismiss()
        } label: {
          HStack {
            Text(conversation.title.isEmpty ? "Untitled" : conversation.title)
              .multilineTextAlignment(.leading)
            Spacer()
            if conversation.id == currentId {
              Image(systemName: "checkmark")
            }
          }
        }
      }
      if truncated {
        Text("More threads on iPhone")
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
    }
    .navigationTitle("Threads")
  }
}
