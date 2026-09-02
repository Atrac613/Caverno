import SwiftUI

/// Answers a model-initiated `ask_user_question`. Single-select answers
/// immediately on tap; multi-select accumulates and sends on confirm.
struct QuestionView: View {
  @EnvironmentObject private var client: WatchSessionClient
  let question: WatchQuestion

  @State private var selected: Set<String> = []

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
        }

        if question.allowMultiple {
          Button {
            client.resolveQuestion(
              id: question.id,
              selectedOptionIds: Array(selected)
            )
          } label: {
            Label("Send", systemImage: "paperplane.fill")
              .frame(maxWidth: .infinity)
          }
          .disabled(selected.isEmpty)
        }

        if question.optionsTruncated || question.allowOther {
          // The wire model caps the option list, so the watch must not present
          // a partial list as if it were the whole choice.
          Text("More options on iPhone")
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
      }
      .padding(.horizontal, 4)
    }
    .navigationTitle("Question")
  }

  private func choose(_ option: WatchQuestionOption) {
    if question.allowMultiple {
      if selected.contains(option.id) {
        selected.remove(option.id)
      } else {
        selected.insert(option.id)
      }
    } else {
      client.resolveQuestion(id: question.id, selectedOptionIds: [option.id])
    }
  }
}
