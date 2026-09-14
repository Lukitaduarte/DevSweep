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

    private var roots: [String] {
        projectRoots.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

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
