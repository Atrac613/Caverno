import SwiftUI

/// Answers a model-initiated `ask_user_question`. Single-select answers
/// immediately on tap; multi-select accumulates and sends on confirm.
struct QuestionView: View {
  @EnvironmentObject private var client: WatchSessionClient
  @Environment(\.dismiss) private var dismiss
  let question: WatchQuestion

  @State private var selected: Set<String> = []
  @State private var commandId: String?

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 10) {
        Text(question.question)
          .font(.headline)

        ForEach(question.options) { option in
          Button {
            choose(option)
          } label: {
            HStack {
              Text(option.label)
                .multilineTextAlignment(.leading)
              Spacer()
              if question.allowMultiple && selected.contains(option.id) {
                Image(systemName: "checkmark")
              }
            }
          }
          .disabled(isSubmitting)
        }

        if question.allowMultiple {
          Button {
            commandId = client.resolveQuestion(
              id: question.id,
              selectedOptionIds: Array(selected)
            )
          } label: {
            Label("Send", systemImage: "paperplane.fill")
              .frame(maxWidth: .infinity)
          }
          .disabled(selected.isEmpty || isSubmitting)
        }

        if question.optionsTruncated || question.allowOther {
          // The wire model caps the option list, so the watch must not present
          // a partial list as if it were the whole choice.
          Text("More options on iPhone")
            .font(.caption2)
            .foregroundStyle(.secondary)
        }

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
    .navigationTitle("Question")
    .onChange(of: client.lastCommandResult?.id) { _, resultId in
      guard resultId == commandId else { return }
      if client.lastCommandResult?.ok == true {
        dismiss()
      }
    }
    .onChange(of: client.snapshot?.question?.id) { _, pendingId in
      if pendingId != question.id { dismiss() }
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

  private func choose(_ option: WatchQuestionOption) {
    if question.allowMultiple {
      if selected.contains(option.id) {
        selected.remove(option.id)
      } else {
        selected.insert(option.id)
      }
    } else {
      commandId = client.resolveQuestion(
        id: question.id,
        selectedOptionIds: [option.id]
      )
    }
  }
}
