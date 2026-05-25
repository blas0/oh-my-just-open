import AppKit
import SwiftUI

struct TypeRowView: View {
    let type: ManagedType
    @Bindable var cache: DefaultsCache
    let onPick: (AppInfo) -> Void

    @State private var showAllInstalled: Bool = false
    @State private var allInstalled: [AppInfo] = []

    private var currentDefault: AppInfo? {
        cache.entries[type.id, default: nil]
    }

    private var selectableApps: [AppInfo] {
        showAllInstalled ? allInstalled : type.claimingApps
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(type.displayLabel)
                    .font(.system(.body, design: .monospaced))
                if !type.secondaryLabel.isEmpty {
                    Text(type.secondaryLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(minWidth: 160, alignment: .leading)

            Spacer(minLength: 8)

            picker

            Toggle(isOn: $showAllInstalled) {
                Text("All apps")
                    .font(.caption)
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .help("Show every installed app, not just apps that explicitly claim this type")
            .onChange(of: showAllInstalled) { _, newValue in
                if newValue && allInstalled.isEmpty {
                    allInstalled = LaunchServicesManager.allInstalledCandidates(for: type.kind)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .task {
            _ = cache.value(for: type)
        }
    }

    @ViewBuilder
    private var picker: some View {
        let candidates = selectableApps
        Menu {
            ForEach(candidates) { app in
                Button {
                    onPick(app)
                } label: {
                    HStack {
                        Text(app.displayName)
                        if app.bundleIdentifier == currentDefault?.bundleIdentifier {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
            if candidates.isEmpty {
                Text("No apps claim this type")
            }
        } label: {
            HStack(spacing: 6) {
                if let current = currentDefault {
                    AppIconView(app: current).frame(width: 16, height: 16)
                    Text(current.displayName).lineLimit(1)
                } else {
                    Image(systemName: "questionmark.circle")
                    Text("None").foregroundStyle(.secondary)
                }
            }
            .frame(minWidth: 160, alignment: .leading)
        }
        .menuStyle(.button)
        .fixedSize()
    }
}

struct AppIconView: NSViewRepresentable {
    let app: AppInfo

    func makeNSView(context: Context) -> NSImageView {
        let v = NSImageView()
        v.imageScaling = .scaleProportionallyUpOrDown
        v.image = app.icon
        return v
    }

    func updateNSView(_ nsView: NSImageView, context: Context) {
        nsView.image = app.icon
    }
}
