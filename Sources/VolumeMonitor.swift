import Foundation
import Combine

/// 单个卷的容量信息。
struct VolumeInfo: Identifiable, Equatable {
    let id: String          // 挂载路径，作为稳定标识
    let name: String
    let isInternal: Bool
    let total: Int          // 字节
    let available: Int      // 字节（优先用 ImportantUsage，更贴近系统显示的可用空间）

    var used: Int { max(0, total - available) }
    var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }
    var freeFraction: Double { total > 0 ? Double(available) / Double(total) : 0 }
}

/// 枚举并监控所有可见卷。最多保留 4 个用于显示，内置盘固定第一，其余按名称稳定排序。
/// 读写速度按需采样（仅在详情打开时），通过 resetSpeeds/refreshSpeeds 控制。
final class VolumeMonitor: ObservableObject {
    @Published private(set) var volumes: [VolumeInfo] = []
    @Published private(set) var speeds: [String: IOSpeed] = [:]

    static let maxCount = 4
    private let sampler = IOSampler()

    private let keys: [URLResourceKey] = [
        .volumeNameKey,
        .volumeIsInternalKey,
        .volumeIsBrowsableKey,
        .volumeTotalCapacityKey,
        .volumeAvailableCapacityKey,
        .volumeAvailableCapacityForImportantUsageKey,
        .volumeIsRootFileSystemKey
    ]

    func refresh() {
        let fm = FileManager.default
        guard let urls = fm.mountedVolumeURLs(
            includingResourceValuesForKeys: keys,
            options: [.skipHiddenVolumes]
        ) else { return }

        var result: [VolumeInfo] = []
        for url in urls {
            guard let v = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            if v.volumeIsBrowsable == false { continue }
            let total = v.volumeTotalCapacity ?? 0
            if total <= 0 { continue }

            let importantAvail = (v.volumeAvailableCapacityForImportantUsage).map { Int($0) } ?? 0
            let plainAvail = v.volumeAvailableCapacity ?? 0
            let available = importantAvail > 0 ? importantAvail : plainAvail

            let name = v.volumeName ?? url.lastPathComponent
            let isInternal = v.volumeIsInternal ?? (v.volumeIsRootFileSystem ?? false)
            result.append(VolumeInfo(id: url.path, name: name, isInternal: isInternal,
                                     total: total, available: available))
        }

        result.sort { a, b in
            if a.isInternal != b.isInternal { return a.isInternal }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }

        let limited = Array(result.prefix(Self.maxCount))
        if limited != volumes { volumes = limited }
    }

    /// 详情打开时调用：清空速度基线。
    func resetSpeeds() {
        sampler.reset()
        if !speeds.isEmpty { speeds = [:] }
    }

    /// 采样一次读写速度（每秒调用一次）。
    func refreshSpeeds() {
        let s = sampler.sample(volumes: volumes)
        if s != speeds { speeds = s }
    }
}
