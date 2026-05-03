import Foundation
import Observation
import Carbon

@Observable
final class AppSettings {
    var retentionPeriod: RetentionPeriod {
        didSet {
            UserDefaults.standard.set(retentionPeriod.rawValue, forKey: Keys.retentionDays)
        }
    }

    var capturePaused: Bool {
        didSet {
            UserDefaults.standard.set(capturePaused, forKey: Keys.capturePaused)
        }
    }

    var shortcutKeyCode: UInt32 {
        didSet {
            UserDefaults.standard.set(Int(shortcutKeyCode), forKey: Keys.shortcutKeyCode)
        }
    }

    var shortcutModifiers: UInt32 {
        didSet {
            UserDefaults.standard.set(Int(shortcutModifiers), forKey: Keys.shortcutModifiers)
        }
    }

    var showDockIcon: Bool {
        didSet {
            UserDefaults.standard.set(showDockIcon, forKey: Keys.showDockIcon)
        }
    }

    init() {
        let days = UserDefaults.standard.integer(forKey: Keys.retentionDays)
        retentionPeriod = RetentionPeriod(rawValue: days) ?? .sevenDays
        capturePaused = UserDefaults.standard.bool(forKey: Keys.capturePaused)
        showDockIcon = UserDefaults.standard.bool(forKey: Keys.showDockIcon)

        let storedKeyCode = UserDefaults.standard.object(forKey: Keys.shortcutKeyCode) as? Int
        let storedModifiers = UserDefaults.standard.object(forKey: Keys.shortcutModifiers) as? Int
        shortcutKeyCode = UInt32(storedKeyCode ?? kVK_ANSI_V)
        shortcutModifiers = UInt32(storedModifiers ?? (cmdKey | shiftKey))
    }

    var shortcutDisplayName: String {
        ShortcutFormatter.displayName(keyCode: shortcutKeyCode, modifiers: shortcutModifiers)
    }

    private enum Keys {
        static let retentionDays = "retentionDays"
        static let capturePaused = "capturePaused"
        static let shortcutKeyCode = "shortcutKeyCode"
        static let shortcutModifiers = "shortcutModifiers"
        static let showDockIcon = "showDockIcon"
    }
}
