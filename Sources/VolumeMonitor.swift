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

/// 枚举并监控所有可见卷。最多保留 4 个用于显示；默认内置盘第一，用户排序后按保存顺序显示。
/// 读写速度按需采样（详情或桌面组件可见时），通过 resetSpeeds/refreshSpeeds 控制。
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

        result = Self.defaultSorted(result)
        result = Self.applyStoredOrder(result, order: AppSettings.shared.volumeOrder)

        let limited = Array(result.prefix(Self.maxCount))
        if limited != volumes { volumes = limited }
    }

    func moveVisibleVolume(from source: IndexSet, to destination: Int) {
        let moved = Self.moved(volumes, from: source, to: destination)
        guard moved != volumes else { return }
        AppSettings.shared.setVisibleVolumeOrder(moved.map(\.id))
        volumes = moved
    }

    func moveVisibleVolume(id sourceID: String, to targetID: String) {
        guard sourceID != targetID,
              let source = volumes.firstIndex(where: { $0.id == sourceID }),
              let target = volumes.firstIndex(where: { $0.id == targetID })
        else { return }

        let destination = target > source ? target + 1 : target
        moveVisibleVolume(from: IndexSet(integer: source), to: destination)
    }

    /// 开始显示实时速度时调用：清空速度基线。
    func resetSpeeds() {
        sampler.reset()
        if !speeds.isEmpty { speeds = [:] }
    }

    /// 采样一次读写速度，并按显示精度量化以减少无意义 UI 刷新。
    func refreshSpeeds() {
        let s = sampler.sample(volumes: volumes).mapValues(Self.displayRounded)
        if s != speeds { speeds = s }
    }

    private static func displayRounded(_ speed: IOSpeed) -> IOSpeed {
        IOSpeed(read: displayRounded(speed.read), write: displayRounded(speed.write))
    }

    private static func displayRounded(_ bytesPerSec: Double) -> Double {
        roundedSpeedForDisplay(bytesPerSec)
    }

    private static func defaultSorted(_ values: [VolumeInfo]) -> [VolumeInfo] {
        values.sorted(by: defaultPrecedes)
    }

    private static func defaultPrecedes(_ a: VolumeInfo, _ b: VolumeInfo) -> Bool {
        if a.isInternal != b.isInternal { return a.isInternal }
        return a.name.localizedStandardCompare(b.name) == .orderedAscending
    }

    private static func applyStoredOrder(_ values: [VolumeInfo], order: [String]) -> [VolumeInfo] {
        guard !order.isEmpty else { return values }
        let positions = Dictionary(uniqueKeysWithValues: AppSettings.uniquePreservingOrder(order).enumerated().map {
            ($0.element, $0.offset)
        })
        return values.sorted { a, b in
            switch (positions[a.id], positions[b.id]) {
            case let (ai?, bi?):
                return ai < bi
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                return defaultPrecedes(a, b)
            }
        }
    }

    private static func moved<T>(_ values: [T], from source: IndexSet, to destination: Int) -> [T] {
        guard !source.isEmpty else { return values }
        var result = values
        let moving = source.sorted().map { values[$0] }
        for index in source.sorted(by: >) { result.remove(at: index) }
        let removedBeforeDestination = source.filter { $0 < destination }.count
        let insertion = max(0, min(result.count, destination - removedBeforeDestination))
        result.insert(contentsOf: moving, at: insertion)
        return result
    }
}
