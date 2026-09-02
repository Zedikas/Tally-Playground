import SwiftUI

extension ResetReminder {
    var v15SystemImage: String { systemImage }
}

struct ExactValueEditor: View {
    @EnvironmentObject private var store: TallyStore
    @Environment(\.dismiss) private var dismiss
    let counter: TallyCounter
    @State private var valueText: String

    init(counter: TallyCounter) {
        self.counter = counter
        _valueText = State(initialValue: String(counter.value))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Exact Value") {
                    TextField("Value", text: $valueText)
                        .keyboardType(.numbersAndPunctuation)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text(counter.isLocked ? "Unlock this counter before changing its value." : "Enter a positive or negative whole number. The change is recorded in History and can be undone.")
                        .font(.caption)
                        .foregroundStyle(counter.isLocked ? .orange : .secondary)
                }
            }
            .navigationTitle(counter.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Set") {
                        guard let value = Int(valueText.trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
                        store.safeSetExactValue(counter, to: value)
                        dismiss()
                    }
                    .disabled(counter.isLocked || Int(valueText.trimmingCharacters(in: .whitespacesAndNewlines)) == nil)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
