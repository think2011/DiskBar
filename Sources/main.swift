import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private let monitor = VolumeMonitor()
    private var capacityTimer: Timer?   // 3s：容量 + 菜单栏图标（仅详情关闭时刷新图标）
    private var speedTimer: Timer?      // 1s：读写速度（仅详情打开时运行，不触碰菜单栏图标）
    private var lastClosed: Date?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.imagePosition = .imageOnly
            button.toolTip = Localization.shared.t("硬盘使用情况", "Disk Usage")
        }

        popover.behavior = .transient
        popover.animates = false   // 配合手动定位，关闭缩放动画以免浮窗位置闪跳
        popover.delegate = self
        let detail = DetailView(
            monitor: monitor,
            onSelect: { [weak self] vol in self?.openInFinder(vol) },
            onQuit: { NSApp.terminate(nil) }
        )
        popover.contentViewController = NSHostingController(rootView: detail)

        monitor.refresh()
        updateStatusImage()

        let t = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.monitor.refresh()
            // 详情打开时不动菜单栏图标，避免 status item 重新布局把浮窗挤偏。
            if !self.popover.isShown { self.updateStatusImage() }
        }
        RunLoop.main.add(t, forMode: .common)
        capacityTimer = t
    }

    private func updateStatusImage() {
        statusItem.button?.image = renderStatusImage(volumes: monitor.volumes)
    }

    @objc private func togglePopover(_ sender: Any?) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            if let last = lastClosed, Date().timeIntervalSince(last) < 0.25 { return }
            guard let button = statusItem.button else { return }
            // 不在 show 前改 image，保证 button 布局稳定、定位准确。
            // NSStatusBarButton 为翻转坐标，.maxY 才是视觉下方（浮窗落在状态栏下方）。
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .maxY)
            // 成为 key window，.transient 才能在点击外部（含桌面）时自动关闭。
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    // MARK: - NSPopoverDelegate

    func popoverDidShow(_ notification: Notification) {
        repositionPopover()
        // 成为 key window，.transient 才能在点击外部（含桌面）时自动关闭。
        popover.contentViewController?.view.window?.makeKey()
        monitor.resetSpeeds()
        monitor.refreshSpeeds()
        let t = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.monitor.refresh()
            self.monitor.refreshSpeeds()   // 0.5s 实时刷新；只刷新详情数据，不触碰菜单栏图标
        }
        RunLoop.main.add(t, forMode: .common)
        speedTimer = t
    }

    func popoverDidClose(_ notification: Notification) {
        lastClosed = Date()
        speedTimer?.invalidate()
        speedTimer = nil
        updateStatusImage()   // 关闭后补一次菜单栏刷新
    }

    /// 系统对状态栏 popover 的自动定位在本机有垂直偏差，手动把浮窗放到图标正下方。
    private func repositionPopover() {
        guard let bw = statusItem.button?.window,
              let pw = popover.contentViewController?.view.window else { return }
        let x = bw.frame.midX - pw.frame.width / 2
        let y = bw.frame.minY - pw.frame.height
        pw.setFrameOrigin(NSPoint(x: x, y: y))
    }

    /// 在访达中打开：内置主盘 → Downloads；外接盘 → 其挂载点。
    private func openInFinder(_ vol: VolumeInfo) {
        let url: URL
        if vol.isInternal {
            url = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: (NSHomeDirectory() as NSString).appendingPathComponent("Downloads"))
        } else {
            url = URL(fileURLWithPath: vol.id)
        }
        NSWorkspace.shared.open(url)
        popover.performClose(nil)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // 纯菜单栏 app，无 Dock 图标
app.run()
