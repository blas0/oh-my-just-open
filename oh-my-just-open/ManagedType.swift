import Foundation
import UniformTypeIdentifiers

struct ManagedType: Identifiable, Hashable {
    let kind: HandlerKind
    let claimingApps: [AppInfo]

    var id: String { kind.displayKey }
    var displayLabel: String { kind.displayLabel }
    var secondaryLabel: String { kind.secondaryLabel }

    var isHighImpactFileType: Bool {
        if case .fileType(let utType) = kind {
            let highImpactExts: Set<String> = ["pdf", "zip", "dmg", "html", "txt"]
            if let ext = utType.preferredFilenameExtension {
                return highImpactExts.contains(ext.lowercased())
            }
        }
        return false
    }

    var alwaysConfirms: Bool {
        if case .urlScheme = kind { return true }
        return isHighImpactFileType
    }
}
