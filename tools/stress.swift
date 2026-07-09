import Foundation
import Darwin

private struct Latencies {
    private var values: [Double] = []

    var count: Int { values.count }

    mutating func record(_ seconds: Double) {
        values.append(seconds * 1000)
    }

    func summary(label: String) -> String {
        guard !values.isEmpty else {
            return "\(label)_count=0 \(label)_p50_ms=0.000 \(label)_p95_ms=0.000 \(label)_max_ms=0.000"
        }
        let sorted = values.sorted()
        return "\(label)_count=\(values.count) " +
            "\(label)_p50_ms=\(fmt(percentile(sorted, 0.50))) " +
            "\(label)_p95_ms=\(fmt(percentile(sorted, 0.95))) " +
            "\(label)_max_ms=\(fmt(sorted.last ?? 0))"
    }
}

private func percentile(_ sorted: [Double], _ p: Double) -> Double {
    guard !sorted.isEmpty else { return 0 }
    let index = min(sorted.count - 1, max(0, Int((Double(sorted.count - 1) * p).rounded())))
    return sorted[index]
}

private func fmt(_ value: Double) -> String {
    String(format: "%.3f", value)
}

private func argDouble(_ name: String, default defaultValue: Double) -> Double {
    let args = CommandLine.arguments
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return defaultValue }
    return Double(args[i + 1]) ?? defaultValue
}

private func timevalSeconds(_ tv: timeval) -> Double {
    Double(tv.tv_sec) + Double(tv.tv_usec) / 1_000_000
}

private func processCPUSeconds() -> Double {
    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)
    return timevalSeconds(usage.ru_utime) + timevalSeconds(usage.ru_stime)
}

private func measure(_ stats: inout Latencies, _ body: () -> Void) {
    let start = DispatchTime.now().uptimeNanoseconds
    body()
    let end = DispatchTime.now().uptimeNanoseconds
    stats.record(Double(end - start) / 1_000_000_000)
}

@main
struct StressMain {
    static func main() {
        let duration = max(1, argDouble("--duration", default: 30))
        let speedInterval = max(0.1, argDouble("--speed-interval", default: 1))
        let capacityInterval = max(0.5, argDouble("--capacity-interval", default: 3))

        let monitor = VolumeMonitor()
        var speedStats = Latencies()
        var capacityStats = Latencies()

        monitor.refresh()
        monitor.resetSpeeds()

        let wallStart = Date()
        let cpuStart = processCPUSeconds()
        var nextSpeed = 0.0
        var nextCapacity = 0.0

        while true {
            let elapsed = Date().timeIntervalSince(wallStart)
            if elapsed >= duration { break }

            if elapsed + 0.000_001 >= nextCapacity {
                measure(&capacityStats) { monitor.refresh() }
                nextCapacity += capacityInterval
            }

            if elapsed + 0.000_001 >= nextSpeed {
                measure(&speedStats) { monitor.refreshSpeeds() }
                nextSpeed += speedInterval
            }

            let afterWork = Date().timeIntervalSince(wallStart)
            let nextWake = min(duration, nextSpeed, nextCapacity)
            let sleepFor = max(0.001, min(0.05, nextWake - afterWork))
            Thread.sleep(forTimeInterval: sleepFor)
        }

        let wall = Date().timeIntervalSince(wallStart)
        let cpu = processCPUSeconds() - cpuStart
        let cpuPct = wall > 0 ? cpu / wall * 100 : 0

        print("duration_s=\(fmt(wall))")
        print("speed_interval_s=\(fmt(speedInterval)) capacity_interval_s=\(fmt(capacityInterval))")
        print("cpu_s=\(fmt(cpu)) cpu_pct=\(fmt(cpuPct))")
        print("volumes=\(monitor.volumes.count) speed_entries=\(monitor.speeds.count)")
        print(capacityStats.summary(label: "capacity"))
        print(speedStats.summary(label: "speed"))
    }
}
