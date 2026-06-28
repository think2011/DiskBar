import AppKit

/// 按 1000 进制格式化字节数，与 Finder / 厂商标称容量一致。
/// 例：1000.8GB -> "1.0 TB"，877.1GB -> "877.1 GB"
func formatBytes(_ bytes: Int) -> String {
    let b = Double(max(0, bytes))
    let kb = 1000.0
    let mb = kb * 1000
    let gb = mb * 1000
    let tb = gb * 1000
    if b >= tb { return String(format: "%.1f TB", b / tb) }
    if b >= gb { return String(format: "%.1f GB", b / gb) }
    if b >= mb { return String(format: "%.0f MB", b / mb) }
    if b >= kb { return String(format: "%.0f KB", b / kb) }
    return "\(Int(b)) B"
}

func percentInt(_ fraction: Double) -> Int {
    Int((fraction * 100).rounded())
}

/// 菜单栏里用的盘名简称：内置盘统一显示 "Mac"，外接盘用卷名（过长则截断）。
func shortLabel(_ v: VolumeInfo) -> String {
    if v.isInternal { return "Mac" }
    let name = v.name
    return name.count > 6 ? String(name.prefix(5)) + "…" : name
}

/// 详情面板里进度条 / 数字的颜色：低占用蓝色，接近满变橙、红，用于预警。
func colorForUsage(_ used: Double) -> NSColor {
    switch used {
    case ..<0.75: return .systemBlue
    case ..<0.90: return .systemOrange
    default:      return .systemRed
    }
}
