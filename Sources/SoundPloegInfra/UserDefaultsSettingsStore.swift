import Foundation
import Carbon
import SoundPloegCore

public final class UserDefaultsSettingsStore: SettingsStore {
    private enum Keys {
        static let selectedVoiceID = "selectedVoiceID"
        static let speechRate = "speechRate"
        static let autoSpeakOnHotkey = "autoSpeakOnHotkey"
        static let hotkeyKeyCode = "hotkeyKeyCode"
        static let hotkeyModifiers = "hotkeyModifiers"
        static let hotkeyDisplayName = "hotkeyDisplayName"
        static let preferredModelRootPath = "preferredModelRootPath"
        static let speechHistoryData = "speechHistoryData"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        registerDefaults()
    }

    public var selectedVoiceID: String? {
        get { defaults.string(forKey: Keys.selectedVoiceID) }
        set { defaults.set(newValue, forKey: Keys.selectedVoiceID) }
    }

    public var speechRate: Float {
        get { defaults.float(forKey: Keys.speechRate) }
        set { defaults.set(newValue, forKey: Keys.speechRate) }
    }

    public var autoSpeakOnHotkey: Bool {
        get { defaults.bool(forKey: Keys.autoSpeakOnHotkey) }
        set { defaults.set(newValue, forKey: Keys.autoSpeakOnHotkey) }
    }

    public var hotkeyShortcut: HotkeyShortcut {
        get {
            HotkeyShortcut(
                keyCode: UInt32(defaults.integer(forKey: Keys.hotkeyKeyCode)),
                carbonModifiers: UInt32(defaults.integer(forKey: Keys.hotkeyModifiers)),
                displayName: defaults.string(forKey: Keys.hotkeyDisplayName) ?? "⌘⇧S"
            )
        }
        set {
            defaults.set(Int(newValue.keyCode), forKey: Keys.hotkeyKeyCode)
            defaults.set(Int(newValue.carbonModifiers), forKey: Keys.hotkeyModifiers)
            defaults.set(newValue.displayName, forKey: Keys.hotkeyDisplayName)
        }
    }

    public var preferredModelRootPath: String? {
        get { defaults.string(forKey: Keys.preferredModelRootPath) }
        set { defaults.set(newValue, forKey: Keys.preferredModelRootPath) }
    }

    public var speechHistoryData: Data? {
        get { defaults.data(forKey: Keys.speechHistoryData) }
        set { defaults.set(newValue, forKey: Keys.speechHistoryData) }
    }

    private func registerDefaults() {
        defaults.register(defaults: [
            Keys.speechRate: 1.0,
            Keys.autoSpeakOnHotkey: true,
            Keys.hotkeyKeyCode: 1,
            Keys.hotkeyModifiers: Int(cmdKey | shiftKey),
            Keys.hotkeyDisplayName: "⌘⇧S"
        ])
    }
}
