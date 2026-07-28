import SwiftUI

struct FigmaTabBar<Selection: Hashable>: View {
    struct Item: Identifiable {
        let id: Selection
        let label: String
        init(_ label: String, _ id: Selection) {
            self.label = label
            self.id = id
        }
    }

    let items: [Item]
    @Binding var selection: Selection

    @Namespace private var indicatorNS

    private let gradientTop = Color(red: 240/255, green: 240/255, blue: 240/255)        // #F0F0F0
    private let gradientBottom = Color(red: 243/255, green: 243/255, blue: 243/255)     // #F3F3F3
    private let outerStroke = Color(red: 227/255, green: 227/255, blue: 227/255)        // #E3E3E3
    private let textActive = Color(red: 25/255, green: 25/255, blue: 25/255)            // #191919
    private let textInactive = Color(red: 201/255, green: 201/255, blue: 201/255)       // #C9C9C9

    private let outerCorner: CGFloat = 10
    private let innerInset: CGFloat = 2

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: outerCorner, style: .continuous)
                .fill(LinearGradient(
                    colors: [gradientTop, gradientBottom],
                    startPoint: .top,
                    endPoint: .bottom
                ))
                .overlay(
                    RoundedRectangle(cornerRadius: outerCorner, style: .continuous)
                        .strokeBorder(outerStroke, lineWidth: 1)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: outerCorner - 1, style: .continuous)
                        .inset(by: 1)
                        .strokeBorder(Color.white, lineWidth: 1)
                )

            HStack(spacing: 3) {
                ForEach(items) { item in
                    tabButton(item)
                }
            }
            .padding(.horizontal, innerInset)
        }
        .frame(width: 270, height: 30)
        .clipShape(RoundedRectangle(cornerRadius: outerCorner, style: .continuous))
    }

    @ViewBuilder
    private func tabButton(_ item: Item) -> some View {
        let isSelected = item.id == selection
        Button {
            withAnimation(.smooth(duration: 0.28, extraBounce: 0.02)) {
                selection = item.id
            }
        } label: {
            ZStack {
                if isSelected {
                    RoundedRectangle(cornerRadius: outerCorner - innerInset, style: .continuous)
                        .fill(Color.white)
                        .overlay(
                            RoundedRectangle(cornerRadius: outerCorner - innerInset, style: .continuous)
                                .strokeBorder(outerStroke, lineWidth: 1)
                        )
                        .matchedGeometryEffect(id: "tabIndicator", in: indicatorNS)
                }
                Text(item.label)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(isSelected ? textActive : textInactive)
            }
            .frame(width: 87, height: 26)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .focusEffectDisabled()
        .accessibilityIdentifier(item.label)
    }
}
