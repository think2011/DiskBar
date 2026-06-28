import Foundation
import IOKit

/// 单个卷的实时读写速度（字节/秒）。
struct IOSpeed: Equatable {
    var read: Double
    var write: Double
}

/// 采样物理盘的累计 I/O，按时间差算出每个卷的实时读写速度。
/// Apple Silicon 上 APFS 卷位于合成虚拟盘，通过递归遍历物理盘的 IORegistry 子树映射回物理盘。
final class IOSampler {
    private var lastByDisk: [String: (read: Int64, write: Int64)] = [:]
    private var lastTime: Date?

    func reset() {
        lastByDisk = [:]
        lastTime = nil
    }

    /// 采样并返回 [volume.id: IOSpeed]。首次调用只建立基线，返回空。
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

        lastByDisk = disks.mapValues { ($0.read, $0.write) }
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
