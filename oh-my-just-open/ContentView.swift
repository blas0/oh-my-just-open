import SwiftUI

struct ContentView: View {
    enum Section: Hashable { case urls, files, about }

    @State private var discovery = AppDiscovery()
    @State private var selected: Section = .urls

    private static let windowSize = CGSize(width: 900, height: 640)

    private var navTitle: String {
        switch selected {
        case .urls:  "URL Schemes"
        case .files: "File Types"
        case .about: "About"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            FigmaTabBar(
                items: [
                    .init("URLs", .urls),
                    .init("Files", .files),
                    .init("About", .about),
                ],
                selection: $selected
            )
            .padding(.leading, 31)
            .padding(.top, 22)
            .padding(.bottom, 12)

            Group {
                switch selected {
                case .urls:
                    TypeListView(
                        title: "URL Schemes",
                        types: discovery.urlSchemeTypes,
                        isLoading: discovery.isLoading
                    )
                case .files:
                    TypeListView(
                        title: "File Types",
                        types: discovery.fileTypes,
                        isLoading: discovery.isLoading
                    )
                case .about:
                    AboutView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: Self.windowSize.width, height: Self.windowSize.height)
        .navigationTitle(navTitle)
        .toolbar { refreshButton }
        .task { discovery.loadIfNeeded() }
    }

    @ToolbarContentBuilder
    private var refreshButton: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                Task { await discovery.refresh() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(discovery.isLoading || selected == .about)
            .opacity(selected == .about ? 0 : 1)
        }
    }
}

#Preview {
    ContentView()
}
