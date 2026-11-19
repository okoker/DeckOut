import DeckCore
import SwiftUI

/// ▶ Test: runs the action in the deck controller exactly as a press would, and shows what it printed or what went
/// wrong.
struct TestRow: View {
    let choice: ActionChoice
    let run: () async -> ActionResult?
    @State private var result: ActionResult?
    @State private var running = false
    @State private var noAnswer = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Button {
                    running = true
                    noAnswer = false
                    result = nil
                    Task {
                        let outcome = await run()
                        result = outcome
                        noAnswer = outcome == nil
                        running = false
                    }
                } label: {
                    Label("Test", systemImage: "play.fill")
                }
                .disabled(choice == .nothing || running)
                if running {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Runs it now, the same way\na key press does.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            if noAnswer {
                FieldNote(text: "The deck controller didn't answer.", warning: true).padding(.leading, -68)
            }
            if let result { ResultView(result: result) }
        }
        .onChange(of: choice) { _, _ in
            result = nil
            noAnswer = false
        }
    }
}

private struct ResultView: View {
    let result: ActionResult

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let error = result.error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color(rgb: 0xFF453A))
            } else if let status = result.exitStatus {
                Label(status == 0 ? "Finished" : "Finished with exit status \(status)",
                      systemImage: status == 0 ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundStyle(status == 0 ? Color(rgb: 0x30D158) : Color(rgb: 0xFF9F0A))
            } else {
                Label("Done", systemImage: "checkmark.circle.fill").foregroundStyle(Color(rgb: 0x30D158))
            }
            let output = [result.stdout, result.stderr].filter { !$0.isEmpty }.joined(separator: "\n")
            if !output.isEmpty {
                ScrollView {
                    Text(output)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 90)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05)))
            }
        }
        .font(.system(size: 11.5))
    }
}
