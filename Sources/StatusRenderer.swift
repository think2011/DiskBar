import AppKit

/// 把若干卷渲染成菜单栏图标：横向排列，每列上方一条迷你实心进度条（实心=占用），下方盘名简称。
/// 默认输出单色 template 图标，由系统根据菜单栏背景自动反色为黑/白，无彩色。
func renderStatusImage(volumes: [VolumeInfo],
                       height: CGFloat = 20,
                       textColor: NSColor = .black,
                       asTemplate: Bool = true) -> NSImage {
    let count = max(1, min(volumes.count, VolumeMonitor.maxCount))
    let labelFont = NSFont.systemFont(ofSize: 7.5, weight: .medium)
    let labAttrs: [NSAttributedString.Key: Any] = [.font: labelFont, .foregroundColor: textColor]

    let barWidth: CGFloat = 24
    let barHeight: CGFloat = 6

    var labels: [NSAttributedString] = []
    var colWidths: [CGFloat] = []
    for i in 0..<count {
        let lab = NSAttributedString(string: shortLabel(volumes[i]), attributes: labAttrs)
        labels.append(lab)
        colWidths.append(max(barWidth, ceil(lab.size().width)))
    }

    let gap: CGFloat = 8
    let sidePad: CGFloat = 1
    let totalW = colWidths.reduce(0, +) + gap * CGFloat(count - 1) + sidePad * 2

    let image = NSImage(size: NSSize(width: ceil(totalW), height: height))
    image.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high

    var x = sidePad
    for i in 0..<count {
        let colW = colWidths[i]
        let frac = min(max(volumes[i].usedFraction, 0), 1)

        // 进度条（顶部）
        let bx = x + (colW - barWidth) / 2
        let by = height - 1 - barHeight
        let radius = barHeight / 2
        let trackRect = NSRect(x: bx, y: by, width: barWidth, height: barHeight)
        textColor.withAlphaComponent(0.25).setFill()
        NSBezierPath(roundedRect: trackRect, xRadius: radius, yRadius: radius).fill()
        if frac > 0.01 {
            let fillW = max(barHeight, barWidth * CGFloat(frac))
            textColor.setFill()
            NSBezierPath(roundedRect: NSRect(x: bx, y: by, width: fillW, height: barHeight),
                         xRadius: radius, yRadius: radius).fill()
        }

        // 盘名（底部）
        let lab = labels[i]
        let ls = lab.size()
        lab.draw(at: NSPoint(x: x + (colW - ls.width) / 2, y: -1))

        x += colW + gap
    }

    image.unlockFocus()
    image.isTemplate = asTemplate
    return image
}
