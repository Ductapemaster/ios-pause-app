import FamilyControls
import SwiftUI

/// Apple's app picker, presented in our own sheet so that choosing apps and
/// saving them are separate acts.
///
/// The `.familyActivityPicker` modifier cannot express this: it flips its
/// `isPresented` binding on any dismissal and gives no way to tell a deliberate
/// save from a swipe, so every tap in the sheet is committed the moment the
/// sheet goes away. Here the picker edits a draft that only `Save` hands back —
/// Cancel, a swipe, or anything else leaves the caller's selection untouched.
struct AppPickerSheet: View {
    /// The selection to open with, mirroring what Pause covers today.
    let initialSelection: FamilyActivitySelection
    let explanation: String
    let onSave: (FamilyActivitySelection) -> Void

    @State private var draft: FamilyActivitySelection
    @Environment(\.dismiss) private var dismiss

    init(
        initialSelection: FamilyActivitySelection,
        explanation: String,
        onSave: @escaping (FamilyActivitySelection) -> Void
    ) {
        self.initialSelection = initialSelection
        self.explanation = explanation
        self.onSave = onSave
        _draft = State(initialValue: initialSelection)
    }

    var body: some View {
        NavigationStack {
            FamilyActivityPicker(footerText: explanation, selection: $draft)
                .navigationTitle("Choose apps")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            let saved = draft
                            dismiss()
                            onSave(saved)
                        }
                    }
                }
        }
    }
}
