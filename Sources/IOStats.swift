import Foundation
import IOKit

/// 单个卷的实时读写速度（字节/秒）。
struct IOSpeed: Equatable {
    var read: Double
    var write: Double
}

/// 采样物理盘累计 I/O，按相邻两次采样的差值算出瞬时读写速度（实时、灵敏）。
/// 注意：对直接拷贝文件等原生连续 I/O 平滑准确；对 docker/OrbStack 等缓冲写入，物理盘是
/// 突发式 flush（攒一批猛刷），瞬时速度会随之起伏 —— 这是物理写入与网络速度的本质差异，非 bug。
/// Apple Silicon 上 APFS 卷在合成虚拟盘，通过递归遍历物理盘 IORegistry 子树映射回物理盘。
final class IOSampler {
    private var lastByDisk: [String: (read: Int64, write: Int64)] = [:]
    private var lastTime: Date?

    func reset() {
        lastByDisk = [:]
        lastTime = nil
    }

    func sample(volumes: [VolumeInfo]) -> [String: IOSpeed] {
        let disks = Self.physicalDisks()
        let now = Date()
        let dt = lastTime.map { now.timeIntervalSince($0) } ?? 0

        // 卷挂载点 -> 物理盘
        var volDisk: [String: String] = [:]
        for vol in volumes {
            guard let part = Self.devicePartition(forPath: vol.id) else { continue }
            for (whole, info) in disks where info.members.contains(part) {
                volDisk[vol.id] = whole
                break
            }
        }

        var speeds: [String: IOSpeed] = [:]
        if dt > 0 {
            for (volID, whole) in volDisk {
                guard let cur = disks[whole], let prev = lastByDisk[whole] else { continue }
                let r = Double(max(0, cur.read - prev.read)) / dt
                let w = Double(max(0, cur.write - prev.write)) / dt
                speeds[volID] = IOSpeed(read: r, write: w)
            }
        }

        var base: [String: (read: Int64, write: Int64)] = [:]
        for (whole, info) in disks { base[whole] = (info.read, info.write) }
        lastByDisk = base
        lastTime = now
        return speeds
    }

    // MARK: - IOKit

    private static func bsdName(_ e: io_registry_entry_t) -> String? {
        IORegistryEntryCreateCFProperty(e, "BSD Name" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? String
    }

    private static func collectBSD(_ entry: io_registry_entry_t, into set: inout Set<String>) {
        var iter: io_iterator_t = 0
        guard IORegistryEntryGetChildIterator(entry, "IOService", &iter) == KERN_SUCCESS else { return }
        var child = IOIteratorNext(iter)
        while child != 0 {
            if let n = bsdName(child) { set.insert(n) }
            collectBSD(child, into: &set)
            IOObjectRelease(child)
            child = IOIteratorNext(iter)
        }
        IOObjectRelease(iter)
    }

    /// [物理盘 BSD: (members: 子树所有分区名, 累计读, 累计写)]
    private static func physicalDisks() -> [String: (members: Set<String>, read: Int64, write: Int64)] {
        var out: [String: (Set<String>, Int64, Int64)] = [:]
        var it: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault,
                                           IOServiceMatching("IOBlockStorageDriver"), &it) == KERN_SUCCESS else { return out }
        var drv = IOIteratorNext(it)
        while drv != 0 {
            var whole: String?
            var child: io_registry_entry_t = 0
            if IORegistryEntryGetChildEntry(drv, "IOService", &child) == KERN_SUCCESS {
                whole = bsdName(child)
                IOObjectRelease(child)
            }
            if let whole {
                var members = Set<String>([whole])
                collectBSD(drv, into: &members)
                var r: Int64 = 0, w: Int64 = 0
                if let stats = IORegistryEntryCreateCFProperty(drv, "Statistics" as CFString, kCFAllocatorDefault, 0)?
                    .takeRetainedValue() as? [String: Any] {
                    r = (stats["Bytes (Read)"] as? Int64) ?? 0
                    w = (stats["Bytes (Write)"] as? Int64) ?? 0
                }
                out[whole] = (members, r, w)
            }
            IOObjectRelease(drv)
            drv = IOIteratorNext(it)
        }
        IOObjectRelease(it)
        return out
    }

    /// 卷挂载路径 -> 分区设备名（如 "disk3s1s1"）。
    private static func devicePartition(forPath path: String) -> String? {
        var fs = statfs()
        guard statfs(path, &fs) == 0 else { return nil }
        let from = withUnsafePointer(to: &fs.f_mntfromname) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1024) { String(cString: $0) }
        }
        return from.hasPrefix("/dev/") ? String(from.dropFirst(5)) : from
    }
}

/// 格式化速度：0 B/s、4 KB/s、1.4 MB/s（1000 进制）。
func formatSpeed(_ bytesPerSec: Double) -> String {
    let b = max(0, bytesPerSec)
    let kb = 1000.0, mb = 1000.0 * 1000, gb = 1000.0 * 1000 * 1000
    if b >= gb { return String(format: "%.1f GB/s", b / gb) }
    if b >= mb { return String(format: "%.1f MB/s", b / mb) }
    if b >= kb { return String(format: "%.0f KB/s", b / kb) }
    return "\(Int(b)) B/s"
}
