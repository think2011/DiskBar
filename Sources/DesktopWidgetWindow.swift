import AppKit
import SwiftUI
import Combine

/// Owns the optional desktop-level widget window.
final class DesktopWidgetController: NSObject, NSWindowDelegate {
    private let monitor: VolumeMonitor
    private let onSelect: (VolumeInfo) -> Void
    private let frameKey = "DesktopWidgetFrame"
    private let widgetWidth = DesktopWidgetView.preferredWidth
    private var panel: NSPanel?
    private var volumeCancellable: AnyCancellable?
    private var isProgrammaticFrameChange = false

    var onVisibilityChange: (() -> Void)?

    var isShown: Bool {
        panel?.isVisible == true
    }

    init(monitor: VolumeMonitor, onSelect: @escaping (VolumeInfo) -> Void) {
        self.monitor = monitor
        self.onSelect = onSelect
        super.init()

        volumeCancellable = monitor.$volumes
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard self?.isShown == true else { return }
                self?.resizeToFitContent()
            }
    }

    func setVisible(_ visible: Bool) {
        visible ? show() : hide()
    }

    private func show() {
        if panel == nil { panel = makePanel() }
        resizeToFitContent()
        panel?.orderFrontRegardless()
        onVisibilityChange?()
    }

    private func hide() {
        panel?.orderOut(nil)
        onVisibilityChange?()
    }

    private func makePanel() -> NSPanel {
        let root = DesktopWidgetView(monitor: monitor, onSelect: onSelect)
        let hosting = NSHostingController(rootView: root)
        let panel = NSPanel(
            contentRect: restoredFrame() ?? defaultFrame(),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.contentViewController = hosting
        panel.delegate = self
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)

        return panel
    }

    private func resizeToFitContent() {
        guard let panel, let view = panel.contentViewController?.view else { return }
        let oldTop = panel.frame.maxY
        let fitting = view.fittingSize
        let height = max(120, fitting.height)
        var newFrame = NSRect(
            x: panel.frame.minX,
            y: oldTop - height,
            width: widgetWidth,
            height: height
        )
        newFrame = constrainedFrame(newFrame)

        guard !NSEqualRects(newFrame, panel.frame) else { return }
        isProgrammaticFrameChange = true
        panel.setFrame(newFrame, display: true)
        saveFrame()
        isProgrammaticFrameChange = false
    }

    private func restoredFrame() -> NSRect? {
        guard let raw = UserDefaults.standard.string(forKey: frameKey) else { return nil }
        let frame = NSRectFromString(raw)
        guard frame.width >= 240, frame.height >= 120 else { return nil }
        guard NSScreen.screens.contains(where: { $0.frame.intersects(frame) }) else {
            return defaultFrame()
        }
        let constrained = constrainedFrame(frame)
        if !NSEqualRects(constrained, frame) {
            UserDefaults.standard.set(NSStringFromRect(constrained), forKey: frameKey)
        }
        return constrained
    }

    private func defaultFrame() -> NSRect {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = NSSize(width: widgetWidth, height: 300)
        return NSRect(
            x: screen.maxX - size.width - 24,
            y: screen.maxY - size.height - 48,
            width: size.width,
            height: size.height
        )
    }

    private func constrainedFrame(_ frame: NSRect) -> NSRect {
        guard let screen = screenVisibleFrame(for: frame) else { return frame }
        var out = frame
        out.origin.x = min(max(out.minX, screen.minX + 8), screen.maxX - out.width - 8)
        out.origin.y = min(max(out.minY, screen.minY + 8), screen.maxY - out.height - 8)
        return out
    }

    private func screenVisibleFrame(for frame: NSRect) -> NSRect? {
        if let screen = NSScreen.screens.first(where: { $0.frame.intersects(frame) }) {
            return screen.visibleFrame
        }
        return NSScreen.main?.visibleFrame
    }

    private func saveFrame() {
        guard let panel else { return }
        UserDefaults.standard.set(NSStringFromRect(panel.frame), forKey: frameKey)
    }

    func windowDidMove(_ notification: Notification) {
        guard !isProgrammaticFrameChange else { return }
        guard let panel else { return }
        let constrained = constrainedFrame(panel.frame)
        if !NSEqualRects(constrained, panel.frame) {
            isProgrammaticFrameChange = true
            panel.setFrame(constrained, display: true)
            isProgrammaticFrameChange = false
        }
        saveFrame()
    }
}
