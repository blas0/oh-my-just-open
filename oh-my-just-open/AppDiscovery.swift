import AppKit
import Foundation
import Observation
import UniformTypeIdentifiers

@MainActor
@Observable
final class AppDiscovery {
    var isLoading: Bool = false
    var apps: [AppInfo] = []
    var appsByID: [String: AppInfo] = [:]
    var urlSchemeTypes: [ManagedType] = []
    var fileTypes: [ManagedType] = []

    func loadIfNeeded() {
        guard urlSchemeTypes.isEmpty && fileTypes.isEmpty && !isLoading else { return }
        Task { await refresh() }
    }

    func refresh() async {
        isLoading = true
        let urls = await SpotlightAppFinder.findAllApps()
        let extras = AppDiscovery.fallbackFilesystemAppURLs()
        let combined = AppDiscovery.dedupe(urls + extras)
        let result = await Task.detached(priority: .userInitiated) {
            AppDiscovery.discover(from: combined)
        }.value
        self.apps = result.apps
        self.appsByID = Dictionary(uniqueKeysWithValues: result.apps.map { ($0.bundleIdentifier, $0) })
        self.urlSchemeTypes = result.urlSchemes
        self.fileTypes = result.fileTypes
        self.isLoading = false
    }

    private struct DiscoveryResult {
        let apps: [AppInfo]
        let urlSchemes: [ManagedType]
        let fileTypes: [ManagedType]
    }

    nonisolated private static func dedupe(_ urls: [URL]) -> [URL] {
        var seen: Set<URL> = []
        var out: [URL] = []
        for url in urls {
            let std = url.standardizedFileURL
            if seen.insert(std).inserted { out.append(std) }
        }
        return out
    }

    nonisolated private static func discover(from bundleURLs: [URL]) -> DiscoveryResult {
        var appsByID: [String: AppInfo] = [:]
        var schemeToApps: [String: Set<String>] = [:]
        var utiToApps: [String: Set<String>] = [:]
        var extToUTI: [String: UTType] = [:]

        for url in bundleURLs {
            guard let bundle = Bundle(url: url) else { continue }
            guard let bundleID = bundle.bundleIdentifier else { continue }
            let info = bundle.infoDictionary ?? [:]
            let name = (info["CFBundleDisplayName"] as? String)
                ?? (info["CFBundleName"] as? String)
                ?? url.deletingPathExtension().lastPathComponent
            let app = AppInfo(bundleURL: url, bundleIdentifier: bundleID, displayName: name)
            if appsByID[bundleID] == nil {
                appsByID[bundleID] = app
            }

            if let urlTypes = info["CFBundleURLTypes"] as? [[String: Any]] {
                for entry in urlTypes {
                    if let schemes = entry["CFBundleURLSchemes"] as? [String] {
                        for raw in schemes {
                            let scheme = raw.lowercased()
                            guard !scheme.isEmpty else { continue }
                            schemeToApps[scheme, default: []].insert(bundleID)
                        }
                    }
                }
            }

            if let docTypes = info["CFBundleDocumentTypes"] as? [[String: Any]] {
                for entry in docTypes {
                    if let utis = entry["LSItemContentTypes"] as? [String] {
                        for uti in utis {
                            utiToApps[uti, default: []].insert(bundleID)
                            if let t = UTType(uti), extToUTI[t.identifier] == nil {
                                extToUTI[t.identifier] = t
                            }
                        }
                    }
                    if let exts = entry["CFBundleTypeExtensions"] as? [String] {
                        for raw in exts {
                            let ext = raw.lowercased().trimmingCharacters(in: .punctuationCharacters)
                            guard !ext.isEmpty, ext != "*" else { continue }
                            if let t = UTType(filenameExtension: ext) {
                                utiToApps[t.identifier, default: []].insert(bundleID)
                                if extToUTI[t.identifier] == nil {
                                    extToUTI[t.identifier] = t
                                }
                            }
                        }
                    }
                }
            }
        }

        let allApps = Array(appsByID.values).sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }

        let urlSchemeTypes: [ManagedType] = schemeToApps
            .map { (scheme, ids) -> ManagedType in
                let appList = ids.compactMap { appsByID[$0] }
                    .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
                return ManagedType(kind: .urlScheme(scheme), claimingApps: appList)
            }
            .sorted { $0.displayLabel.localizedCaseInsensitiveCompare($1.displayLabel) == .orderedAscending }

        let fileTypes: [ManagedType] = utiToApps
            .compactMap { (utiID, ids) -> ManagedType? in
                guard let t = UTType(utiID) ?? extToUTI[utiID] else { return nil }
                if t.preferredFilenameExtension == nil { return nil }
                let appList = ids.compactMap { appsByID[$0] }
                    .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
                return ManagedType(kind: .fileType(t), claimingApps: appList)
            }
            .sorted { $0.displayLabel.localizedCaseInsensitiveCompare($1.displayLabel) == .orderedAscending }

        return DiscoveryResult(apps: allApps, urlSchemes: urlSchemeTypes, fileTypes: fileTypes)
    }

    nonisolated private static func fallbackFilesystemAppURLs() -> [URL] {
        let fm = FileManager.default
        var roots: [URL] = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            URL(fileURLWithPath: "/System/Library/CoreServices/Applications"),
            URL(fileURLWithPath: "/Library/CoreServices/Applications"),
        ]
        if let home = fm.urls(for: .applicationDirectory, in: .userDomainMask).first {
            roots.append(home)
        }
        var found: [URL] = []
        for root in roots {
            guard let enumerator = fm.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: nil
            ) else { continue }
            for case let url as URL in enumerator {
                if url.pathExtension == "app" {
                    found.append(url)
                    enumerator.skipDescendants()
                }
            }
        }
        return found
    }
}
