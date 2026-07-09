import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// 点击菜单栏图标后弹出的详情卡片。macOS 原生「储存空间」风格，支持中英文。
/// 每行可点击 → 在访达中打开对应位置；显示实时读写速度（详情 0.5 秒，桌面组件 1 秒）。
struct DetailView: View {
    @ObservedObject var monitor: VolumeMonitor
    @ObservedObject private var loc = Localization.shared
    @ObservedObject private var login = LoginManager.shared
    @ObservedObject private var settings = AppSettings.shared
    var onSelect: (VolumeInfo) -> Void = { _ in }
    var onQuit: () -> Void = {}
    var allowsReordering: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(loc.t("储存空间", "Storage"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 6)

            CompactVolumeList(monitor: monitor, onSelect: onSelect, allowsReordering: allowsReordering)
            .padding(.horizontal, 8)
            .padding(.bottom, 6)

            Divider().padding(.horizontal, 12)

            VStack(spacing: 7) {
                HStack(spacing: 12) {
                    Toggle(isOn: Binding(get: { login.enabled }, set: { login.set($0) })) {
                        Text(loc.t("开机启动", "Launch at login"))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .toggleStyle(.checkbox)

                    Spacer(minLength: 8)

                    Toggle(isOn: $settings.desktopWidgetEnabled) {
                        Text(loc.t("桌面组件", "Desktop widget"))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .toggleStyle(.checkbox)
                }

                HStack(spacing: 10) {
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
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .frame(width: 308)
    }
}

/// Desktop card version of the expanded storage panel.
struct DesktopWidgetView: View {
    static let preferredWidth: CGFloat = 268

    @ObservedObject var monitor: VolumeMonitor
    @ObservedObject private var loc = Localization.shared
    var onSelect: (VolumeInfo) -> Void = { _ in }
    var allowsReordering: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(loc.t("储存空间", "Storage"))
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                Text(loc.t("实时速度", "Live speed"))
                    .font(.system(size: 9, weight: .medium))
                    .monospacedDigit()
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.top, 9)

            CompactVolumeList(monitor: monitor, onSelect: onSelect, allowsReordering: allowsReordering)
            .padding(.horizontal, 6)
            .padding(.bottom, 7)
        }
        .frame(width: Self.preferredWidth)
        .fixedSize(horizontal: false, vertical: true)
        .background(
            Color(nsColor: .windowBackgroundColor).opacity(0.88),
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(Color.primary.opacity(0.10), lineWidth: 0.5)
        )
        .padding(1)
    }
}

private struct CompactVolumeList: View {
    @ObservedObject var monitor: VolumeMonitor
    var onSelect: (VolumeInfo) -> Void
    var allowsReordering: Bool
    @State private var draggingID: String?
    @State private var activeDropTargetID: String?

    var body: some View {
        VStack(spacing: 1) {
            ForEach(monitor.volumes) { vol in
                row(for: vol)
            }
        }
    }

    @ViewBuilder
    private func row(for vol: VolumeInfo) -> some View {
        let base = CompactVolumeRow(vol: vol, speed: monitor.speeds[vol.id])
            .contentShape(Rectangle())
            .onTapGesture { onSelect(vol) }

        if allowsReordering {
            base
                .onDrag {
                    draggingID = vol.id
                    activeDropTargetID = nil
                    return NSItemProvider(object: vol.id as NSString)
                }
                .onDrop(
                    of: [.plainText],
                    delegate: VolumeReorderDropDelegate(
                        targetVolume: vol,
                        draggingID: $draggingID,
                        activeDropTargetID: $activeDropTargetID,
                        move: { sourceID, targetID in
                            monitor.moveVisibleVolume(id: sourceID, to: targetID)
                        }
                    )
                )
        } else {
            base
        }
    }
}

private struct VolumeReorderDropDelegate: DropDelegate {
    let targetVolume: VolumeInfo
    @Binding var draggingID: String?
    @Binding var activeDropTargetID: String?
    let move: (String, String) -> Void

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard draggingID != nil else { return nil }
        return DropProposal(operation: .move)
    }

    func dropEntered(info: DropInfo) {
        guard let draggingID,
              draggingID != targetVolume.id,
              activeDropTargetID != targetVolume.id
        else { return }

        activeDropTargetID = targetVolume.id
        withAnimation(.easeInOut(duration: 0.12)) {
            move(draggingID, targetVolume.id)
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        let wasInternalDrag = draggingID != nil
        draggingID = nil
        activeDropTargetID = nil
        return wasInternalDrag
    }
}

private struct CompactVolumeRow: View {
    let vol: VolumeInfo
    let speed: IOSpeed?
    @ObservedObject private var loc = Localization.shared
    @State private var hovering = false

    private var barColor: Color {
        switch vol.usedFraction {
        case ..<0.75: return .primary.opacity(0.78)
        case ..<0.90: return .orange
        default:      return .red
        }
    }

    private var availableText: String {
        loc.isZh ? "\(formatBytes(vol.available)) 可用" : "\(formatBytes(vol.available)) free"
    }

    var body: some View {
        HStack(alignment: .center, spacing: 7) {
            Image(systemName: vol.isInternal ? "internaldrive" : "externaldrive")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.primary.opacity(0.62))
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(vol.name)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    Text("\(percentInt(vol.usedFraction))%")
                        .font(.system(size: 10, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(.primary.opacity(0.68))
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.13))
                        Capsule()
                            .fill(barColor)
                            .frame(width: max(3, geo.size.width * vol.usedFraction))
                    }
                }
                .frame(height: 3)

                HStack(spacing: 5) {
                    Text(availableText)
                        .font(.system(size: 9))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    CompactSpeedLabel(symbol: "arrow.down", value: speed?.read)
                    CompactSpeedLabel(symbol: "arrow.up", value: speed?.write)
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(hovering ? Color.primary.opacity(0.08) : Color.clear)
        )
        .onHover { hovering = $0 }
    }
}

private struct CompactSpeedLabel: View {
    let symbol: String
    let value: Double?

    var body: some View {
        let active = (value ?? 0) >= 1
        HStack(spacing: 2) {
            Image(systemName: symbol)
                .font(.system(size: 8, weight: .bold))
            Text(formatSpeed(value ?? 0))
                .font(.system(size: 9, weight: active ? .semibold : .regular))
                .monospacedDigit()
        }
        .foregroundStyle(active ? AnyShapeStyle(.primary.opacity(0.82)) : AnyShapeStyle(.tertiary))
    }
}
