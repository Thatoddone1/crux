//
//  ReportMessageView.swift
//  Crux
//

import SwiftUI

/// Sheet for reporting a single message: optional reason, submit, confirmation.
/// Doesn't remove the message from the timeline — it just tells the server.
struct ReportMessageView: View {
    let message: TimelineModel.Message
    let model: TimelineModel

    @Environment(\.dismiss) private var dismiss
    @State private var reason = ""
    @State private var isSubmitting = false
    @State private var isSubmitted = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(message.body)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                Section("Reason (optional)") {
                    TextField("What's wrong with this message?", text: $reason, axis: .vertical)
                        .lineLimit(3...6)
                }
                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle("Report Message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSubmitted {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else if isSubmitting {
                        ProgressView()
                    } else {
                        Button("Submit", action: submit)
                    }
                }
            }
            .disabled(isSubmitted)
        }
    }

    private func submit() {
        isSubmitting = true
        errorMessage = nil
        Task {
            do {
                try await model.report(message, reason: reason.isEmpty ? nil : reason)
                isSubmitting = false
                isSubmitted = true
                try? await Task.sleep(for: .seconds(1))
                dismiss()
            } catch {
                isSubmitting = false
                errorMessage = error.localizedDescription
            }
        }
    }
}
