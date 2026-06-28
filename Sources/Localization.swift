import Foundation
import Combine

enum AppLanguage: String {
    case zh, en
}

/// 中英文本地化。首次启动按系统语言自动判断默认值，之后在中 / 英之间切换并持久化。
final class Localization: ObservableObject {
    static let shared = Localization()
    private let key = "DiskBarLanguage"

    @Published var language: AppLanguage {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: key) }
    }

    private init() {
        if let saved = UserDefaults.standard.string(forKey: key),
           let lang = AppLanguage(rawValue: saved) {
            language = lang
        } else {
            // 首次使用：跟随系统语言，非中文一律回退英文
            let pref = Locale.preferredLanguages.first ?? "en"
            language = pref.hasPrefix("zh") ? .zh : .en
        }
    }

    var isZh: Bool { language == .zh }

    /// 取本地化文案：第一个参数中文，第二个英文。
    func t(_ zh: String, _ en: String) -> String { isZh ? zh : en }

    /// 切换按钮上显示的当前语言名。
    var languageName: String { isZh ? "中文" : "EN" }

    /// 在中 / 英之间切换。
    func toggleLanguage() {
        language = isZh ? .en : .zh
    }
}
