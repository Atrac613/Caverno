import SwiftUI

/// The reason this app exists: answer a blocked turn without taking the phone
/// out.
struct ApprovalView: View {
  @EnvironmentObject private var client: WatchSessionClient
  let approval: WatchApproval

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 10) {
        Label(kindLabel, systemImage: kindSymbol)
          .font(.caption2)
          .foregroundStyle(.orange)

        Text(approval.title)
          .font(.headline)

        if !approval.subtitle.isEmpty {
          Text(approval.subtitle)
            .font(.caption2)
            .foregroundStyle(.secondary)
        }

        if !approval.detail.isEmpty {
          Text(approval.detail)
            .font(.footnote)
        }

        if approval.canResolveOnWatch {
          Button {
            client.resolveApproval(id: approval.id, approved: true)
          } label: {
            Label("Approve", systemImage: "checkmark")
              .frame(maxWidth: .infinity)
          }
          .tint(.green)

          Button(role: .destructive) {
            client.resolveApproval(id: approval.id, approved: false)
          } label: {
            Label("Deny", systemImage: "xmark")
              .frame(maxWidth: .infinity)
          }
        } else {
          // Kinds that need input the watch cannot collect (SSH credentials,
          // computer-use arming) or that this build does not recognise.
          Text("Continue on iPhone")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 6)
        }

        if let error = client.lastCommandError {
          Text(error)
            .font(.caption2)
            .foregroundStyle(.red)
        }
      }
      .padding(.horizontal, 4)
    }
    .navigationTitle("Approval")
  }

  private var kindLabel: String {
    switch approval.kind {
    case "file": return "File change"
    case "localCommand": return "Shell command"
    case "gitCommand": return "Git command"
    case "sshCommand": return "SSH command"
    case "sshConnect": return "SSH connection"
    case "browserAction": return "Browser action"
    case "bleConnect": return "Bluetooth"
    case "serialOpen": return "Serial port"
    case "computerUse": return "Computer use"
    case "participantTool": return "Participant tool"
    default: return "Approval required"
    }
  }

  private var kindSymbol: String {
    switch approval.kind {
    case "file": return "doc.text"
    case "localCommand", "sshCommand": return "terminal"
    case "gitCommand": return "arrow.triangle.branch"
    case "sshConnect": return "lock.shield"
    case "browserAction": return "globe"
    case "bleConnect": return "dot.radiowaves.left.and.right"
    case "serialOpen": return "cable.connector"
    case "computerUse": return "cursorarrow.rays"
    default: return "exclamationmark.triangle"
    }
  }
}
