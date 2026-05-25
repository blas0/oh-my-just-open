import SwiftUI

@MainActor
@Observable
final class DefaultsCache {
    var entries: [String: AppInfo?] = [:]

    func value(for type: ManagedType) -> AppInfo? {
        if let cached = entries[type.id] { return cached }
        let resolved = LaunchServicesManager.currentDefault(for: type.kind)
        entries[type.id] = resolved
        return resolved
    }

    func updateAfterChange(for type: ManagedType, newApp: AppInfo) {
        entries[type.id] = newApp
    }

    func invalidate(_ type: ManagedType) {
        entries.removeValue(forKey: type.id)
    }
}

struct TypeListView: View {
    let title: String
    let types: [ManagedType]
    let isLoading: Bool

    @State private var searchText: String = ""
    @State private var onlyMultiOption: Bool = true
    @State private var filterByCurrentApp: AppInfo? = nil
    @State private var pendingChange: PendingChange? = nil
    @State private var cache = DefaultsCache()

    private var filteredTypes: [ManagedType] {
        let needle = searchText
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))

        var pool = types
        if onlyMultiOption {
            pool = pool.filter { $0.claimingApps.count > 1 }
        }
        if let filter = filterByCurrentApp {
            pool = pool.filter { type in
                cache.entries[type.id, default: nil]?.bundleIdentifier == filter.bundleIdentifier
            }
        }
        guard !needle.isEmpty else { return pool }

        var prefix: [ManagedType] = []
        var contains: [ManagedType] = []
        for type in pool {
            let label = type.displayLabel.lowercased()
            let key = label.hasPrefix(".") ? String(label.dropFirst()) : label
            if key.hasPrefix(needle) {
                prefix.append(type)
            } else if key.contains(needle) {
                contains.append(type)
            }
        }
        return prefix + contains
    }

    private var currentAppOptions: [AppInfo] {
        var seen: Set<String> = []
        var apps: [AppInfo] = []
        for (_, app) in cache.entries {
            if let app, seen.insert(app.bundleIdentifier).inserted {
                apps.append(app)
            }
        }
        return apps.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if isLoading && types.isEmpty {
                Spacer()
                ProgressView("Scanning installed apps…")
                    .frame(maxWidth: .infinity)
                Spacer()
            } else if filteredTypes.isEmpty {
                Spacer()
                Text("No matches.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                list
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle(title)
        .sheet(item: $pendingChange) { pending in
            ChangeConfirmationSheet(pending: pending) { confirmed in
                if confirmed {
                    Task { await applyChange(pending) }
                }
                pendingChange = nil
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search \(title.lowercased())", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6, style: .continuous))

            HStack(spacing: 8) {
                Toggle(isOn: $onlyMultiOption) {
                    Text("Only types with multiple available apps")
                }
                .toggleStyle(.switch)
                .controlSize(.small)

                Spacer()

                Menu {
                    Button("Any") { filterByCurrentApp = nil }
                    Divider()
                    ForEach(currentAppOptions) { app in
                        Button(app.displayName) { filterByCurrentApp = app }
                    }
                    if currentAppOptions.isEmpty {
                        Text("Scroll to populate")
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("Currently set to:")
                            .foregroundStyle(.secondary)
                        Text(filterByCurrentApp?.displayName ?? "Any")
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
        .padding(12)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(filteredTypes) { type in
                    TypeRowView(
                        type: type,
                        cache: cache,
                        onPick: { newApp in
                            propose(type: type, newApp: newApp)
                        }
                    )
                    Divider()
                }
            }
        }
    }

    private func propose(type: ManagedType, newApp: AppInfo) {
        let current = cache.value(for: type)
        if current?.bundleIdentifier == newApp.bundleIdentifier { return }

        if type.alwaysConfirms {
            pendingChange = PendingChange(
                type: type,
                newApp: newApp,
                currentDefault: current,
                alternatives: type.claimingApps
            )
        } else {
            Task { await apply(type: type, newApp: newApp) }
        }
    }

    private func applyChange(_ pending: PendingChange) async {
        await apply(type: pending.type, newApp: pending.newApp)
    }

    private func apply(type: ManagedType, newApp: AppInfo) async {
        do {
            try await LaunchServicesManager.setDefault(newApp, for: type.kind)
            cache.updateAfterChange(for: type, newApp: newApp)
        } catch {
            cache.invalidate(type)
            NSApp.presentError(error)
        }
    }
}

struct PendingChange: Identifiable {
    let id = UUID()
    let type: ManagedType
    let newApp: AppInfo
    let currentDefault: AppInfo?
    let alternatives: [AppInfo]
}
