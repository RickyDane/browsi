import SwiftUI
import UniformTypeIdentifiers

/// Sidebar button: shows overall progress, bounces when a download lands, opens the queue.
struct DownloadsButton: View {
    @Environment(BrowserState.self) private var browser
    @State private var manager = DownloadManager.shared
    @State private var showQueue = false
    @State private var landed = false

    var body: some View {
        Button { showQueue.toggle() } label: {
            ZStack {
                if let p = manager.overallProgress {
                    Circle().stroke(.primary.opacity(0.12), lineWidth: 2.5)
                    Circle().trim(from: 0, to: max(0.03, p))
                        .stroke(browser.selectedSpace.color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.easeOut(duration: 0.25), value: p)
                }
                Image(systemName: manager.activeCount > 0 ? "arrow.down" : "arrow.down.circle")
                    .font(.system(size: manager.activeCount > 0 ? 10 : 14, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: browser.downloadsBounce)
            }
            .frame(width: 22, height: 22)
            .foregroundStyle(manager.activeCount > 0 ? AnyShapeStyle(browser.selectedSpace.color) : AnyShapeStyle(.secondary))
            .background {
                // Shockwave when a flying file lands.
                Circle().stroke(browser.selectedSpace.color, lineWidth: 2)
                    .scaleEffect(landed ? 2.4 : 0.8)
                    .opacity(landed ? 0 : 0.9)
            }
        }
        .buttonStyle(SquishButtonStyle())
        .padding(-4)
        .help("Downloads")
        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { browser.downloadsButtonFrame = $0 }
        .onDisappear { browser.downloadsButtonFrame = nil }
        .onChange(of: browser.downloadsBounce) {
            landed = false
            withAnimation(.easeOut(duration: Motion.reduceMotion ? 0.01 : 0.55)) { landed = true }
        }
        .popover(isPresented: $showQueue, arrowEdge: .trailing) {
            DownloadsQueueView()
                .environment(browser)
        }
    }
}

struct DownloadsQueueView: View {
    @Environment(BrowserState.self) private var browser
    @State private var manager = DownloadManager.shared

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Downloads").font(.headline)
                Spacer()
                if manager.items.contains(where: { !$0.isActive }) {
                    Button("Clear") { manager.clearFinished() }
                        .buttonStyle(.borderless).font(.system(size: 12))
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            Divider()
            if manager.items.isEmpty {
                ContentUnavailableView("No Downloads", systemImage: "arrow.down.circle",
                                       description: Text("Files you download appear here."))
                    .frame(height: 200)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(manager.items) { item in
                            DownloadRow(item: item)
                                .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity),
                                                        removal: .opacity))
                        }
                    }
                    .padding(6)
                }
                .frame(maxHeight: 420)
            }
            if SmartRenamer.status == .available {
                Divider()
                Label("Click ✦ to give a file a smart name with Apple Intelligence", systemImage: "apple.intelligence")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal, 14).padding(.vertical, 8)
            }
        }
        .frame(width: 380)
    }
}

private struct DownloadRow: View {
    @Environment(BrowserState.self) private var browser
    let item: DownloadItem
    @State private var hovering = false
    @State private var editing = false
    @State private var draftName = ""
    private let manager = DownloadManager.shared

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: icon).resizable().frame(width: 32, height: 32)
                .opacity(item.state == .finished && !item.fileExists ? 0.4 : 1)
            VStack(alignment: .leading, spacing: 3) {
                if editing {
                    TextField("Name", text: $draftName)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { manager.rename(item, to: draftName); editing = false }
                        .onExitCommand { editing = false }
                } else {
                    Text(item.fileName)
                        .font(.system(size: 12.5, weight: .medium))
                        .lineLimit(1).truncationMode(.middle)
                        .contentTransition(.interpolate)
                        .overlay { if item.isRenaming { Shimmer() } }
                }
                detail
            }
            Spacer(minLength: 4)
            actions
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 10).fill(.primary.opacity(hovering ? 0.06 : 0)))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { if item.state == .finished { manager.open(item) } }
        .draggable(item.fileURL ?? URL(fileURLWithPath: "/")) { Image(nsImage: icon) }
        .contextMenu { menu }
    }

    private var icon: NSImage {
        if let url = item.fileURL, item.fileExists { return NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false)) }
        return NSWorkspace.shared.icon(for: UTType(filenameExtension: (item.fileName as NSString).pathExtension) ?? .data)
    }

    @ViewBuilder private var detail: some View {
        switch item.state {
        case .downloading:
            ProgressView(value: item.progress).progressViewStyle(.linear).controlSize(.small)
                .tint(browser.selectedSpace.color)
            Text(byteText).font(.system(size: 10.5)).foregroundStyle(.secondary).monospacedDigit()
        case .finished:
            HStack(spacing: 4) {
                if item.isRenaming {
                    Text("Finding a good name…").foregroundStyle(.purple)
                } else if let old = item.renamedFrom {
                    Image(systemName: "apple.intelligence").foregroundStyle(.purple)
                    Text("was \(old)").lineLimit(1).truncationMode(.middle)
                } else {
                    Text(item.fileExists ? ByteCountFormatter.string(fromByteCount: item.totalBytes, countStyle: .file)
                                         : "Moved or deleted")
                }
            }
            .font(.system(size: 10.5)).foregroundStyle(.secondary)
        case .failed(let message):
            Text(message).font(.system(size: 10.5)).foregroundStyle(.red).lineLimit(1)
        case .cancelled:
            Text("Cancelled").font(.system(size: 10.5)).foregroundStyle(.secondary)
        }
    }

    private var byteText: String {
        let done = ByteCountFormatter.string(fromByteCount: item.receivedBytes, countStyle: .file)
        guard item.totalBytes > 0 else { return done }
        return "\(done) of \(ByteCountFormatter.string(fromByteCount: item.totalBytes, countStyle: .file))"
    }

    @ViewBuilder private var actions: some View {
        HStack(spacing: 2) {
            switch item.state {
            case .downloading:
                iconButton("xmark.circle.fill", "Cancel") { manager.cancel(item) }
            case .finished where item.fileExists:
                if SmartRenamer.status == .available {
                    iconButton("apple.intelligence", "Smart Rename") { Task { await manager.smartRename(item) } }
                        .disabled(item.isRenaming)
                        .symbolEffect(.pulse, options: .repeating, isActive: item.isRenaming)
                }
                iconButton("magnifyingglass.circle.fill", "Show in Finder") { manager.reveal(item) }
            case .failed, .cancelled:
                iconButton("arrow.clockwise.circle.fill", "Retry") { manager.retry(item) }
            default:
                EmptyView()
            }
        }
        .opacity(hovering || item.isActive || item.isRenaming ? 1 : 0.35)
    }

    private func iconButton(_ symbol: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 15)) }
            .buttonStyle(SquishButtonStyle()).padding(-4)
            .foregroundStyle(.secondary)
            .help(help)
    }

    @ViewBuilder private var menu: some View {
        if item.state == .finished, item.fileExists {
            Button("Open") { manager.open(item) }
            Button("Show in Finder") { manager.reveal(item) }
            Divider()
            Button("Smart Rename") { Task { await manager.smartRename(item) } }
                .disabled(SmartRenamer.status != .available || item.isRenaming)
            Button("Rename…") { draftName = (item.fileName as NSString).deletingPathExtension; editing = true }
            if item.renamedFrom != nil { Button("Undo Rename") { manager.undoRename(item) } }
            Divider()
            Button("Move to Trash", role: .destructive) { manager.moveToTrash(item) }
        }
        if let src = item.context.sourceURL {
            Button("Copy Download Link") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(src.absoluteString, forType: .string)
            }
        }
        Button("Remove from List") { manager.remove(item) }
    }
}

/// Sweeping highlight over a label while the model is working.
private struct Shimmer: View {
    @State private var phase: CGFloat = -1
    var body: some View {
        GeometryReader { geo in
            LinearGradient(colors: [.clear, .purple.opacity(0.45), .cyan.opacity(0.45), .clear],
                           startPoint: .leading, endPoint: .trailing)
                .frame(width: geo.size.width * 0.6)
                .offset(x: phase * geo.size.width)
                .blendMode(.plusLighter)
        }
        .clipped()
        .allowsHitTesting(false)
        .onAppear { withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) { phase = 1.2 } }
    }
}

/// A file icon flying from where the user clicked to the downloads button along an arc.
struct DownloadFlightView: View {
    @Environment(BrowserState.self) private var browser
    let flight: DownloadFlight
    let target: CGPoint
    @State private var t: CGFloat = 0

    var body: some View {
        Image(nsImage: flight.icon)
            .resizable()
            .frame(width: 64, height: 64)
            .shadow(color: browser.selectedSpace.color.opacity(0.8), radius: 14)
            .shadow(color: .black.opacity(0.3), radius: 6, y: 4)
            .modifier(ArcFlight(t: t, from: flight.from, to: target))
            .allowsHitTesting(false)
            .onAppear {
                let duration = Motion.reduceMotion ? 0.01 : 0.85
                withAnimation(.timingCurve(0.45, 0, 0.2, 1, duration: duration)) { t = 1 } completion: {
                    browser.landDownloadFlight(flight.id)
                }
            }
    }
}

/// Position on a quadratic Bézier arc plus pop-in, shrink, tilt and fade at the end.
struct ArcFlight: ViewModifier, Animatable {
    var t: CGFloat
    let from: CGPoint
    let to: CGPoint

    var animatableData: CGFloat {
        get { t }
        set { t = newValue }
    }

    func body(content: Content) -> some View {
        let control = CGPoint(x: from.x + (to.x - from.x) * 0.35, y: min(from.y, to.y) - 220)
        let u = 1 - t
        let p = CGPoint(x: u * u * from.x + 2 * u * t * control.x + t * t * to.x,
                        y: u * u * from.y + 2 * u * t * control.y + t * t * to.y)
        let pop: CGFloat = t < 0.12 ? 0.5 + (t / 0.12) * 0.7 : 1.2 - 0.95 * ((t - 0.12) / 0.88)
        return content
            .scaleEffect(max(0.2, pop))
            .rotationEffect(.degrees(Double(-30 * t)))
            .opacity(t > 0.9 ? Double((1 - t) / 0.1) : 1)
            .position(p)
    }
}
