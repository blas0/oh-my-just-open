import SwiftUI

@main
struct oh_my_just_openApp: App {
    @State private var updateService = UpdateService()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updateService.updater)
            }
        }
    }
}
