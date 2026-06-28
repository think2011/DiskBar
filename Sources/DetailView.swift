import SwiftUI
import AppKit

/// 点击菜单栏图标后弹出的详情卡片。macOS 原生「储存空间」风格，支持中英文。
/// 每行可点击 → 在访达中打开对应位置；显示实时读写速度（详情打开时每秒刷新）。
struct DetailView: View {
    @ObservedObject var monitor: VolumeMonitor
    @ObservedObject private var loc = Localization.shared
    @ObservedObject private var login = LoginManager.shared
    var onSelect: (VolumeInfo) -> Void = { _ in }
    var onQuit: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(loc.t("储存空间", "Storage"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 6)

            VStack(spacing: 2) {
                ForEach(monitor.volumes) { vol in
                    VolumeRow(vol: vol, speed: monitor.speeds[vol.id])
                        .contentShape(Rectangle())
                        .onTapGesture { onSelect(vol) }
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 6)

            Divider().padding(.horizontal, 12)

            HStack(spacing: 10) {
                Toggle(isOn: Binding(get: { login.enabled }, set: { login.set($0) })) {
                    Text(loc.t("开机启动", "Launch at login"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .toggleStyle(.checkbox)

                Divider().frame(height: 12)

                Button {
                    loc.toggleLanguage()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "globe").font(.system(size: 12))
                        Text(loc.languageName).font(.system(size: 11))
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(loc.t("切换语言", "Switch language"))

                Spacer()

                Button(action: onQuit) {
                    Text(loc.t("退出", "Quit")).font(.system(size: 11))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .frame(width: 308)
    }
}

private struct VolumeRow: View {
    let vol: VolumeInfo
    let speed: IOSpeed?
    @ObservedObject private var loc = Localization.shared
    @State private var hovering = false

    /// 默认实心中性色（深浅自适应），接近写满时转橙/红预警。
    private var barColor: Color {
        switch vol.usedFraction {
        case ..<0.75: return .primary.opacity(0.85)
        case ..<0.90: return .orange
        default:      return .red
        }
    }

    private var capacityText: String {
        let avail = formatBytes(vol.available)
        let total = formatBytes(vol.total)
        return loc.isZh ? "\(avail) 可用，共 \(total)" : "\(avail) free of \(total)"
    }

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: vol.isInternal ? "internaldrive" : "externaldrive")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(.primary.opacity(0.7))
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(vol.name)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text("\(percentInt(vol.usedFraction))%")
                        .font(.system(size: 12, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.primary.opacity(0.75))
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.14))
                        Capsule()
                            .fill(barColor)
                            .frame(width: max(4, geo.size.width * vol.usedFraction))
                    }
                }
                .frame(height: 5)

                Text(capacityText)
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)

                HStack(spacing: 14) {
                    SpeedLabel(symbol: "arrow.down", value: speed?.read)
                    SpeedLabel(symbol: "arrow.up", value: speed?.write)
                }
                .padding(.top, 1)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(hovering ? Color.primary.opacity(0.08) : Color.clear)
        )
        .onHover { hovering = $0 }
    }
}

private struct SpeedLabel: View {
    let symbol: String
    let value: Double?
    var body: some View {
        let active = (value ?? 0) >= 1
        HStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
            Text(formatSpeed(value ?? 0))
                .font(.system(size: 11))
                .monospacedDigit()
        }
        .foregroundStyle(active ? AnyShapeStyle(.primary.opacity(0.85)) : AnyShapeStyle(.tertiary))
    }
}
