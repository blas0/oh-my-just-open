import Foundation
import UniformTypeIdentifiers

enum HandlerKind: Hashable {
    case urlScheme(String)
    case fileType(UTType)

    var displayKey: String {
        switch self {
        case .urlScheme(let s): return s.lowercased()
        case .fileType(let t): return t.identifier
        }
    }

    var displayLabel: String {
        switch self {
        case .urlScheme(let s):
            return "\(s)://"
        case .fileType(let t):
            if let ext = t.preferredFilenameExtension {
                return ".\(ext)"
            }
            return t.identifier
        }
    }

    var secondaryLabel: String {
        switch self {
        case .urlScheme:
            return ""
        case .fileType(let t):
            return t.localizedDescription ?? t.identifier
        }
    }
}
