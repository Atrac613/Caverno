import SwiftUI

/// Answers a goal the harness has stopped scheduling for.
///
/// `ConversationGoalStatus.awaitingConfirmation` means the harness ran out of
/// work and cannot say the objective was met — the absence of evidence of
/// incompleteness is not evidence of completion, so it asks instead of
/// closing the goal itself. The measured behaviour on the phone is that the
/// model does not volunteer `update_goal` but answers when asked, which makes
/// this a decision worth a wrist rather than a status worth a glance.
struct GoalView: View {
  @EnvironmentObject private var client: WatchSessionClient
  @Environment(\.dismiss) private var dismiss
  let goal: WatchGoal

  @State private var commandId: String?

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 10) {
        Text(goal.objective)
          .font(.headline)

        // The summary is what the harness believes it achieved. Confirming
        // without it is confirming blind, which is the failure this screen
        // exists to avoid.
        if !goal.completionSummary.isEmpty {
          Text(goal.completionSummary)
            .font(.caption2)
            .foregroundStyle(.secondary)
        }

        Button {
          commandId = client.resolveGoal(completed: true)
        } label: {
          Label("Objective met", systemImage: "checkmark.circle.fill")
            .frame(maxWidth: .infinity)
        }
        .disabled(isSubmitting)

        Button {
          commandId = client.resolveGoal(completed: false)
        } label: {
          Label("Keep going", systemImage: "arrow.clockwise")
            .frame(maxWidth: .infinity)
        }
        .disabled(isSubmitting)

        if let error = feedbackError {
          Text(error)
            .font(.caption2)
            .foregroundStyle(.red)
        }

        if isSubmitting {
          HStack {
            ProgressView()
            Text(client.lastCommandNotice ?? "Sending…")
              .font(.caption2)
              .foregroundStyle(.secondary)
          }
          .frame(maxWidth: .infinity, alignment: .center)
        }
      }
      .padding(.horizontal, 4)
    }
    .navigationTitle("Goal")
    // Waits for the correlated result rather than dismissing on tap, the way
    // the approval and question screens do: a failure has to stay on the
    // screen that caused it so it can be retried.
    .onChange(of: client.lastCommandResult?.id) { _, resultId in
      guard resultId == commandId else { return }
      if client.lastCommandResult?.ok == true {
        dismiss()
      }
    }
    .onChange(of: client.snapshot?.goalAwaitingConfirmation == nil) {
      _, resolvedElsewhere in
      if resolvedElsewhere { dismiss() }
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
