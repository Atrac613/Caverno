import SwiftUI

/// Source choice stays separate from the local thread picker so remote rows
/// can never invoke the phone's local conversation selector.
struct WatchSourcesView: View {
  @EnvironmentObject private var client: WatchSessionClient
  @Environment(\.dismiss) private var dismiss
  @State private var localCommandId: String?

  var body: some View {
    List {
      if let snapshot = client.snapshot, snapshot.isLocal {
        NavigationLink("Local chats") {
          ThreadPickerView(
            conversations: snapshot.conversations,
            currentId: snapshot.conversationId,
            truncated: snapshot.conversationsTruncated
          )
        }
      } else {
        Button("Local chats") { localCommandId = client.selectLocalSource() }
      }
      if let browser = client.snapshot?.remoteBrowser {
        NavigationLink {
          RemoteProjectsView()
        } label: {
          VStack(alignment: .leading, spacing: 3) {
            Text("Remote Coding")
            Text(browser.hostName.isEmpty ? "Pair a host on iPhone" : browser.hostName)
              .font(.caption2)
              .foregroundStyle(.secondary)
          }
        }
      }
      if let error = client.lastCommandError {
        Text(error).font(.caption2).foregroundStyle(.red)
      }
    }
    .navigationTitle("Chats")
    .onChange(of: client.snapshot?.isLocal) { _, isLocal in
      if localCommandId != nil && isLocal == true { dismiss() }
    }
    .onChange(of: client.snapshot?.remoteBrowser?.selectionStatus) { _, status in
      if status == "selected" { dismiss() }
    }
  }
}

/// Uses the current snapshot on every render, including while this page is
/// already open. Lists and connection state may change on the other devices.
struct RemoteProjectsView: View {
  @EnvironmentObject private var client: WatchSessionClient
  @State private var commandId: String?

  var body: some View {
    List {
      if let browser = client.snapshot?.remoteBrowser {
        Text(browser.hostName)
          .font(.caption2)
          .foregroundStyle(.secondary)
        if browser.connectionStatus == "unpaired" {
          Text("Pair a host in Remote Coding on iPhone.")
        } else if !browser.isConnected {
          Text("Connect to the host on iPhone.")
          Button("Refresh") { client.requestSnapshot() }
        } else {
          if browser.projectId != nil {
            Button("All projects") { browse(browser, projectId: nil) }
          }
          if browser.selectionStatus == "project_removed" {
            Text("This project was removed.")
          } else if browser.selectionStatus == "thread_removed" {
            Text("This thread was removed.")
          } else if browser.selectionStatus == "changed" {
            Text("The open thread changed on another device.")
          }
          if browser.items.isEmpty {
            Text(browser.projectId == nil ? "No projects" : "No threads in this project")
          }
          ForEach(browser.items) { item in
            Button {
              if browser.projectId == nil {
                browse(browser, projectId: item.id)
              } else {
                commandId = client.selectRemoteConversation(browser, id: item.id)
              }
            } label: {
              HStack {
                Text(item.title.isEmpty ? "Untitled" : item.title)
                  .multilineTextAlignment(.leading)
                Spacer(minLength: 2)
                if browser.conversationId == item.id && browser.selectionStatus == "selected" {
                  Image(systemName: "checkmark")
                }
              }
            }
            .disabled(isSubmitting)
          }
          if browser.offset > 0 {
            Button("Previous") { browse(browser, projectId: browser.projectId, offset: max(0, browser.offset - 8)) }
              .disabled(isSubmitting)
          }
          if browser.offset + browser.items.count < browser.total {
            Button("More") { browse(browser, projectId: browser.projectId, offset: browser.offset + browser.items.count) }
              .disabled(isSubmitting)
          }
        }
        if isSubmitting {
          ProgressView("Loading…")
          if let notice = client.lastCommandNotice { Text(notice).font(.caption2) }
        }
        if let error = client.lastCommandError {
          Text(error).font(.caption2).foregroundStyle(.red)
        }
      }
    }
    .navigationTitle(client.snapshot?.remoteBrowser?.projectId == nil
      ? "Projects" : client.snapshot?.remoteBrowser?.projectTitle ?? "Threads")
    .onAppear {
      if let browser = client.snapshot?.remoteBrowser, browser.isConnected {
        browse(browser, projectId: nil)
      }
    }
  }

  private func browse(_ browser: WatchRemoteBrowser, projectId: String?, offset: Int = 0) {
    commandId = client.browseRemote(browser, projectId: projectId, offset: offset)
  }

  private var isSubmitting: Bool {
    guard let commandId else { return false }
    return client.lastCommandResult?.id != commandId
  }
}

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
            // `ConversationsState.conversations` is unfiltered, so chat,
            // coding and routine threads arrive looking like the same kind of
            // thing. The mode is the difference between picking a chat and
            // picking an agent that is mid-task.
            VStack(alignment: .leading, spacing: 1) {
              Text(conversation.title.isEmpty ? "Untitled" : conversation.title)
                .multilineTextAlignment(.leading)
              if let mode = conversation.mode, mode != .chat {
                Text(mode.label)
                  .font(.caption2)
                  .foregroundStyle(.secondary)
              }
            }
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
