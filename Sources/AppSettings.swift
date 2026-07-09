import Foundation
import Combine

/// User-facing app preferences shared by the menu popover and desktop widget.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    static let volumeOrderKey = "VolumeOrder"

    private static let desktopWidgetKey = "DesktopWidgetEnabled"

    @Published var desktopWidgetEnabled: Bool {
        didSet { UserDefaults.standard.set(desktopWidgetEnabled, forKey: Self.desktopWidgetKey) }
    }

    @Published var volumeOrder: [String] {
        didSet { UserDefaults.standard.set(volumeOrder, forKey: Self.volumeOrderKey) }
    }

    private init() {
        desktopWidgetEnabled = UserDefaults.standard.bool(forKey: Self.desktopWidgetKey)
        volumeOrder = Self.uniquePreservingOrder(
            UserDefaults.standard.stringArray(forKey: Self.volumeOrderKey) ?? []
        )
    }

    func setVisibleVolumeOrder(_ visibleIDs: [String]) {
        let visibleIDs = Self.uniquePreservingOrder(visibleIDs)
        let visible = Set(visibleIDs)
        let hiddenOrMissing = Self.uniquePreservingOrder(volumeOrder).filter { !visible.contains($0) }
        volumeOrder = visibleIDs + hiddenOrMissing
    }

    static func uniquePreservingOrder(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        return ids.filter { seen.insert($0).inserted }
    }
}
