import Foundation

@MainActor
enum SpotlightAppFinder {
    static func findAllApps() async -> [URL] {
        await withCheckedContinuation { (continuation: CheckedContinuation<[URL], Never>) in
            let query = NSMetadataQuery()
            query.predicate = NSPredicate(
                format: "kMDItemContentTypeTree == 'com.apple.application-bundle'"
            )
            query.searchScopes = [NSMetadataQueryLocalComputerScope]
            query.sortDescriptors = []

            final class ObserverBox: @unchecked Sendable { var token: NSObjectProtocol? }
            let box = ObserverBox()

            box.token = NotificationCenter.default.addObserver(
                forName: .NSMetadataQueryDidFinishGathering,
                object: query,
                queue: .main
            ) { _ in
                query.disableUpdates()
                query.stop()

                var urls: [URL] = []
                for i in 0..<query.resultCount {
                    if let item = query.result(at: i) as? NSMetadataItem,
                       let path = item.value(forAttribute: NSMetadataItemPathKey) as? String {
                        urls.append(URL(fileURLWithPath: path))
                    }
                }

                if let token = box.token {
                    NotificationCenter.default.removeObserver(token)
                }
                continuation.resume(returning: urls)
            }

            if !query.start() {
                if let token = box.token {
                    NotificationCenter.default.removeObserver(token)
                }
                continuation.resume(returning: [])
            }
        }
    }
}
