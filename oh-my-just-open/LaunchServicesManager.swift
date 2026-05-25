import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
enum LaunchServicesManager {
    static func currentDefault(for kind: HandlerKind) -> AppInfo? {
        let url: URL?
        switch kind {
        case .urlScheme(let s):
            guard let probe = URL(string: "\(s):") else { return nil }
            url = NSWorkspace.shared.urlForApplication(toOpen: probe)
        case .fileType(let t):
            url = NSWorkspace.shared.urlForApplication(toOpen: t)
        }
        return url.flatMap(appInfo(from:))
    }

    static func allInstalledCandidates(for kind: HandlerKind) -> [AppInfo] {
        let urls: [URL]
        switch kind {
        case .urlScheme(let s):
            guard let probe = URL(string: "\(s):") else { return [] }
            urls = NSWorkspace.shared.urlsForApplications(toOpen: probe)
        case .fileType(let t):
            urls = NSWorkspace.shared.urlsForApplications(toOpen: t)
        }
        let mapped = urls.compactMap(appInfo(from:))
        var seen: Set<String> = []
        return mapped.filter { seen.insert($0.bundleIdentifier).inserted }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    static func setDefault(_ app: AppInfo, for kind: HandlerKind) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            switch kind {
            case .urlScheme(let s):
                NSWorkspace.shared.setDefaultApplication(at: app.bundleURL, toOpenURLsWithScheme: s) { error in
                    if let error { continuation.resume(throwing: error) }
                    else { continuation.resume() }
                }
            case .fileType(let t):
                NSWorkspace.shared.setDefaultApplication(at: app.bundleURL, toOpen: t) { error in
                    if let error { continuation.resume(throwing: error) }
                    else { continuation.resume() }
                }
            }
        }
    }

    private static func appInfo(from url: URL) -> AppInfo? {
        guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { return nil }
        let info = bundle.infoDictionary ?? [:]
        let name = (info["CFBundleDisplayName"] as? String)
            ?? (info["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent
        return AppInfo(bundleURL: url, bundleIdentifier: id, displayName: name)
    }

}
