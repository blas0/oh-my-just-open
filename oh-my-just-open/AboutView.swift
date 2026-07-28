import SwiftUI

struct AboutView: View {
    private static let markdownBody: AttributedString = {
        let raw = """
        A minimal macOS defaults manager.

        **All you need to know:**

        Choose a different default app from any row's menu. URL schemes and high-impact file types prompt for confirmation; other change silently.

        The **All Apps** toggle overrides default app claims. For example, this let's you set **.pdf** types to Helium.

        Changes are applied via `LaunchServices`.
        """
        return makeAttributed(raw)
    }()

    private static let footerSnippet: AttributedString = {
        let raw = """
        For **bugs** and **feature requests**, submit a pull request to the repo.

        [oh-my-just-open](https://github.com/blas0/mac-os-apps/tree/main/oh-my-just-open)
        """
        return makeAttributed(raw)
    }()

    private static func makeAttributed(_ raw: String) -> AttributedString {
        let opts = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        return (try? AttributedString(markdown: raw, options: opts)) ?? AttributedString(raw)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Image("Avatar")
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 128, height: 128)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .accessibilityLabel("oh-my-just-open mascot")

                Text("oh-my-just-open")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))

                Text(Self.markdownBody)
                    .font(.system(size: 14))
                    .tint(.accentColor)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Divider()
                    .padding(.top, 14)

                Text(Self.footerSnippet)
                    .font(.system(size: 14))
                    .tint(.accentColor)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 24)
            .frame(maxWidth: 560, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
