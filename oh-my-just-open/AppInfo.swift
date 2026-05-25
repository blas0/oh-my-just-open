import AppKit
import Foundation

struct AppInfo: Identifiable, Hashable {
    let bundleURL: URL
    let bundleIdentifier: String
    let displayName: String

    var id: String { bundleIdentifier }

    static func == (lhs: AppInfo, rhs: AppInfo) -> Bool {
        lhs.bundleIdentifier == rhs.bundleIdentifier
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(bundleIdentifier)
    }

    var icon: NSImage {
        NSWorkspace.shared.icon(forFile: bundleURL.path)
    }
}
