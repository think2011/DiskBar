import SwiftUI
import AppKit

/// 离屏渲染预览工具：把菜单栏图标和详情卡片导出为 PNG，便于在无屏幕的远程机上验证视觉效果。
@main
struct PreviewMain {
    @MainActor static func main() {
        let monitor = VolumeMonitor()
        monitor.refresh()
        monitor.resetSpeeds()
        monitor.refreshSpeeds()
        Thread.sleep(forTimeInterval: 1.0)
        monitor.refreshSpeeds()
        FileHandle.standardError.write("volumes=\(monitor.volumes.count) speeds=\(monitor.speeds.count)\n".data(using: .utf8)!)

        let composite = renderMenuBarPreview(volumes: monitor.volumes)
        savePNG(composite, to: "/tmp/diskbar_menubar.png")

        Localization.shared.language = .zh
        renderDetail(monitor, to: "/tmp/diskbar_detail.png")
        Localization.shared.language = .en
        renderDetail(monitor, to: "/tmp/diskbar_detail_en.png")
        print("preview done")
    }

    @MainActor static func renderDetail(_ monitor: VolumeMonitor, to path: String) {
        let renderer = ImageRenderer(content: DetailView(monitor: monitor))
        renderer.scale = 2
        if let img = renderer.nsImage { savePNG(img, to: path) }
    }
}

/// 在浅色 / 深色两种菜单栏背景上放大显示图标，验证 template 自适应效果。
@MainActor
func renderMenuBarPreview(volumes: [VolumeInfo]) -> NSImage {
    let scale: CGFloat = 5
    let light = renderStatusImage(volumes: volumes, textColor: .black, asTemplate: false)
    let dark = renderStatusImage(volumes: volumes, textColor: .white, asTemplate: false)
    let iconW = light.size.width * scale
    let iconH = light.size.height * scale
    let pad: CGFloat = 26
    let rowH = iconH + pad * 2
    let W = iconW + pad * 4
    let H = rowH * 2

    let out = NSImage(size: NSSize(width: W, height: H))
    out.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high

    NSColor(white: 0.16, alpha: 1).setFill()
    NSRect(x: 0, y: 0, width: W, height: rowH).fill()
    NSColor(white: 0.95, alpha: 1).setFill()
    NSRect(x: 0, y: rowH, width: W, height: rowH).fill()

    let x = (W - iconW) / 2
    light.draw(in: NSRect(x: x, y: rowH + pad, width: iconW, height: iconH))
    dark.draw(in: NSRect(x: x, y: pad, width: iconW, height: iconH))

    out.unlockFocus()
    return out
}

func savePNG(_ image: NSImage, to path: String) {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { return }
    try? png.write(to: URL(fileURLWithPath: path))
}
