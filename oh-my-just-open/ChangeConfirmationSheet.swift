import SwiftUI

struct ChangeConfirmationSheet: View {
    let pending: PendingChange
    let onResolve: (Bool) -> Void

    private var scope: String {
        switch pending.type.kind {
        case .urlScheme(let s):
            return "All \(s):// links system-wide will open in the chosen app."
        case .fileType:
            return "All files of this type will open in the chosen app when double-clicked or opened from another app."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.title2)
                Text("Change default for \(pending.type.displayLabel)?")
                    .font(.headline)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Currently:").frame(width: 90, alignment: .leading).foregroundStyle(.secondary)
                    Text(pending.currentDefault?.displayName ?? "None")
                }
                HStack {
                    Text("New:").frame(width: 90, alignment: .leading).foregroundStyle(.secondary)
                    Text(pending.newApp.displayName).bold()
                }
                HStack(alignment: .top) {
                    Text("Scope:").frame(width: 90, alignment: .leading).foregroundStyle(.secondary)
                    Text(scope)
                }
            }
            .font(.callout)

            if pending.alternatives.count > 1 {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Other apps that claim this type:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(pending.alternatives
                            .filter { $0.bundleIdentifier != pending.newApp.bundleIdentifier }
                            .map(\.displayName)
                            .joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { onResolve(false) }
                    .keyboardShortcut(.cancelAction)
                Button("Change") { onResolve(true) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}
