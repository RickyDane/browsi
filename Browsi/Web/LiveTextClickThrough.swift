import AppKit
import WebKit

/// When a fullscreen video pauses on a frame with text, WebKit lays VisionKit's Live Text overlay
/// (`VKCImageAnalysisOverlayView`) over the whole web view. That overlay takes every click, so the video
/// and its controls can't be clicked anymore (e.g. to resume playback). This monitor hides the overlay
/// for the duration of a click so the click reaches the page. The overlay's own controls (the Live Text
/// button) keep working, and WebKit removes the overlay once the video plays.
///
/// Turning off WebKit's `TextRecognitionInVideosEnabled` flag is not an option: the web process still
/// sends the recognition request, and the UI process then kills it for sending an invalid message.
final class LiveTextClickThrough {
    static let shared = LiveTextClickThrough()
    private var monitor: Any?
    private weak var hiddenOverlay: NSView?

    func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
            return event
        }
    }

    private func handle(_ event: NSEvent) {
        if event.type == .leftMouseUp {
            // Bring the overlay back after the window has delivered this mouse-up to the page.
            guard let overlay = hiddenOverlay else { return }
            hiddenOverlay = nil
            DispatchQueue.main.async { overlay.isHidden = false }
            return
        }
        guard let frameView = event.window?.contentView?.superview,
              let hit = frameView.hitTest(frameView.convert(event.locationInWindow, from: nil)),
              !(hit is NSControl),
              let overlay = Self.liveTextOverlay(containing: hit) else { return }
        overlay.isHidden = true   // the window hit-tests after this monitor returns, so the click goes to the web view
        hiddenOverlay = overlay
    }

    /// The Live Text overlay `view` belongs to, if it sits inside one hosted by a web view.
    static func liveTextOverlay(containing view: NSView) -> NSView? {
        var current: NSView? = view
        while let v = current, !(v is WKWebView) {
            if isLiveTextOverlay(v), v.superview is WKWebView { return v }
            current = v.superview
        }
        return nil
    }

    static func isLiveTextOverlay(_ view: NSView) -> Bool {
        NSStringFromClass(type(of: view)).contains("ImageAnalysisOverlayView")
    }
}
