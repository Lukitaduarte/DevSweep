import SwiftUI

/// First run: nothing is recommended until the user confirms where their projects live.
///
/// Every "this project is abandoned" judgement — old Flutter SDKs, inactive build folders —
/// is derived from this list. A wrong list makes a pinned SDK look orphaned, so the app asks
/// instead of guessing.
struct WelcomeView: View {
    @AppStorage(Prefs.Key.projectRoots) private var projectRoots = ""
    @AppStorage(Prefs.Key.workspacesConfirmed) private var workspacesConfirmed = false
    let onConfirm: () -> Void

    /// Only folders that exist count: confirming a typo would start recommending with nothing
    /// behind the list.
    private var roots: [String] { WorkspaceDiscovery.existingRoots(in: projectRoots) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(tr("welcome.title")).font(.title3.weight(.semibold))
                Text(tr("welcome.body")).font(.callout).foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(tr("welcome.folders")).font(.caption.weight(.medium))
                TextEditor(text: $projectRoots)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(height: 132)
                    .scrollContentBackground(.hidden)
                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
                Text(tr("welcome.hint")).font(.caption2).foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Image(systemName: roots.isEmpty ? "exclamationmark.triangle.fill" : "folder.fill")
                    .foregroundStyle(roots.isEmpty ? Color.orange : Color.accentColor)
                Text(roots.isEmpty ? tr("welcome.none") : tr("welcome.detected", count: roots.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(tr("welcome.confirm")) {
                // Written explicitly: Prefs.register() supplies projectRoots through the
                // registration domain, which is volatile. Confirming without touching the editor
                // would persist nothing, and a later launch would recompute a different list —
                // one the user never saw — while confirmation stayed true.
                let confirmed = roots.joined(separator: "\n")
                Prefs.defaults.set(confirmed, forKey: Prefs.Key.projectRoots)
                projectRoots = confirmed
                workspacesConfirmed = true
                onConfirm()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(roots.isEmpty)
            .frame(maxWidth: .infinity)

            Text(tr("welcome.changeable")).font(.caption2).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(20)
    }
}
