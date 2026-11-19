import DeckCore
import SwiftUI

/// What the app knows about its agent, as text: used before the real window exists, and in test sessions.
struct DebugView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var link: AgentLink

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(model.identity?.appName ?? "DeckOut") — build \(model.appBuild)").font(.headline)
            if let problem = model.locationProblem { Text(problem).foregroundStyle(.red) }
            Text("Registration: \(model.registration.map { "\($0)" } ?? "…")")
            Text("Link: \(String(describing: link.state))")
            Text("Live strip blocks: \(link.liveStrip.images.keys.sorted().joined(separator: ", "))")
            ScrollView {
                Text(statusText).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
        .onChange(of: link.state) { _, state in model.log("link: \(state)") }
    }

    private var statusText: String {
        guard let status = link.status else { return "No status yet" }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? encoder.encode(status)).flatMap { String(data: $0, encoding: .utf8) } ?? "?"
    }
}
