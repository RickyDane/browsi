import SwiftUI

struct SpaceSwitcher: View {
    @Environment(BrowserState.self) private var browser
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(browser.spaces.enumerated()), id: \.element.id) { i, space in
                let selected = space.id == browser.selectedSpaceID
                Button { browser.switchSpace(to: space) } label: {
                    Image(systemName: space.symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(selected ? AnyShapeStyle(space.color) : AnyShapeStyle(.secondary))
                        .frame(width: 26, height: 26)
                        .background {
                            if selected {
                                Circle().fill(space.color.opacity(0.22))
                                    .matchedGeometryEffect(id: "space", in: ns)
                            }
                        }
                        .symbolEffect(.bounce, value: selected)
                }
                .buttonStyle(SquishButtonStyle(hoverBackground: !selected))
                .padding(-4)
                .help("\(space.name) (⌃\(i + 1))")
                .contextMenu {
                    Button("Rename…") { rename(space) }
                    Menu("Icon") {
                        ForEach(["house.fill", "briefcase.fill", "books.vertical.fill", "gamecontroller.fill",
                                 "airplane", "heart.fill", "star.fill", "leaf.fill", "bolt.fill", "paintpalette.fill"],
                                id: \.self) { sym in
                            Button { space.symbol = sym; browser.scheduleSave() } label: { Label(sym, systemImage: sym) }
                        }
                    }
                    Menu("Color") {
                        ForEach([("Violet", 0.72), ("Blue", 0.58), ("Teal", 0.47), ("Green", 0.36),
                                 ("Orange", 0.08), ("Pink", 0.93)], id: \.0) { name, hue in
                            Button(name) { withAnimation(Motion.smooth) { space.hue = hue }; browser.scheduleSave() }
                        }
                    }
                    Divider()
                    Button("Delete Space", role: .destructive) { browser.delete(space: space) }
                        .disabled(browser.spaces.count < 2)
                }
            }
            Button { browser.addSpace() } label: {
                Image(systemName: "plus").font(.system(size: 12, weight: .semibold)).frame(width: 26, height: 26)
            }
            .buttonStyle(SquishButtonStyle())
            .padding(-4)
            .foregroundStyle(.secondary)
            .help("New Space")
        }
        .animation(Motion.bouncy, value: browser.selectedSpaceID)
    }

    private func rename(_ space: Space) {
        let a = NSAlert()
        a.messageText = "Rename Space"
        let f = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        f.stringValue = space.name
        a.accessoryView = f
        a.addButton(withTitle: "Rename")
        a.addButton(withTitle: "Cancel")
        a.window.initialFirstResponder = f
        if a.runModal() == .alertFirstButtonReturn, !f.stringValue.isEmpty {
            space.name = f.stringValue
            browser.scheduleSave()
        }
    }
}
