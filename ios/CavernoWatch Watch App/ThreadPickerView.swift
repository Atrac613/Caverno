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

  @State private var commandId: String?
  @State private var selectedId: String?

  var body: some View {
    List {
      ForEach(conversations) { conversation in
        Button {
          selectedId = conversation.id
          commandId = client.selectConversation(id: conversation.id)
        } label: {
          HStack {
            Text(conversation.title.isEmpty ? "Untitled" : conversation.title)
              .multilineTextAlignment(.leading)
            Spacer()
            if conversation.id == selectedId && isSubmitting {
              ProgressView()
            } else if conversation.id == currentId {
              Image(systemName: "checkmark")
            }
          }
        }
        .disabled(isSubmitting)
      }
      if truncated {
        Text("More threads on iPhone")
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
      if let error = feedbackError {
        Text(error)
          .font(.caption2)
          .foregroundStyle(.red)
      } else if isSubmitting, let notice = client.lastCommandNotice {
        Text(notice)
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
    }
    .navigationTitle("Threads")
    .onChange(of: client.lastCommandResult?.id) { _, resultId in
      guard resultId == commandId else { return }
      if client.lastCommandResult?.ok == true {
        dismiss()
      }
    }
    .onChange(of: client.snapshot?.conversationId) { _, conversationId in
      if commandId != nil && conversationId == selectedId { dismiss() }
    }
  }

  private var isSubmitting: Bool {
    guard let commandId else { return false }
    return client.lastCommandResult?.id != commandId
  }

  private var feedbackError: String? {
    guard client.lastCommandResult?.id == commandId else { return nil }
    return client.lastCommandError
  }
}
