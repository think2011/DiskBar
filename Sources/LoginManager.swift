import Foundation
import Combine

/// 开机启动管理：用户级 LaunchAgent。勾选则写 plist 并 bootstrap，取消则 bootout 并删除。
/// 用 LaunchAgent 而非 SMAppService，避免手搓（ad-hoc 签名）app 的登录项注册限制。
final class LoginManager: ObservableObject {
    static let shared = LoginManager()
    private let label = "com.think2011.diskbar"

    @Published private(set) var enabled: Bool = false

    private var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    private init() {
        enabled = FileManager.default.fileExists(atPath: plistURL.path)
    }

    func set(_ on: Bool) {
        if on { enable() } else { disable() }
        enabled = FileManager.default.fileExists(atPath: plistURL.path)
    }

    private func enable() {
        guard let exec = Bundle.main.executablePath else { return }
        let dir = plistURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [exec],
            "RunAtLoad": true,
            "ProcessType": "Interactive"
        ]
        guard let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) else { return }
        try? data.write(to: plistURL)
        // 不 bootstrap：bootstrap + RunAtLoad=true 会立刻拉起一个新实例，导致菜单栏出现重复图标。
        // 只写 plist，下次登录由 launchd 的 RunAtLoad 自动启动。
    }

    private func disable() {
        try? FileManager.default.removeItem(at: plistURL)
        launchctl(["bootout", "gui/\(getuid())/\(label)"])   // 清理可能残留的注册，忽略错误
    }

    private func launchctl(_ args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = args
        p.standardOutput = nil
        p.standardError = nil
        try? p.run()
        p.waitUntilExit()
    }
}
