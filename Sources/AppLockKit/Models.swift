import Foundation

/// An application the user has chosen to protect.
struct ProtectedApp: Codable, Identifiable, Hashable {
    var bundleID: String
    var name: String
    var path: String

    var id: String { bundleID }
}

/// A user-facing application discovered on disk, shown in the picker.
struct AppInfo: Identifiable, Hashable {
    let bundleID: String
    let name: String
    let path: URL

    var id: String { bundleID }

    static func == (lhs: AppInfo, rhs: AppInfo) -> Bool { lhs.bundleID == rhs.bundleID }
    func hash(into hasher: inout Hasher) { hasher.combine(bundleID) }
}

/// Every knob the app exposes. Decoded leniently so an older config file keeps
/// working after a field is added.
struct AppSettings: Codable, Equatable {
    /// Re-lock a protected app as soon as the user switches away from it.
    var lockOnAppSwitch: Bool = true
    /// Re-lock everything when the Mac goes to sleep.
    var lockOnSleep: Bool = true
    /// Re-lock everything when the screen is locked.
    var lockOnScreenLock: Bool = true
    /// Re-lock after a period of no keyboard or mouse input.
    var lockOnIdle: Bool = false
    /// Idle timeout, in seconds.
    var idleTimeout: Double = 300
    /// Offer the Touch ID button on the lock screen.
    var allowTouchID: Bool = true
    /// Call Touch ID by itself when the lock screen appears, rather than waiting
    /// for the button to be clicked. Off by default: the system biometric sheet
    /// on every app switch gets in the way of just typing the passcode.
    var autoPromptTouchID: Bool = false
    /// Show a Dock icon so the manager behaves like a normal app.
    var showDockIcon: Bool = true
    /// Start AppLock automatically at login.
    var launchAtLogin: Bool = false
    /// Emergency hotkey that dismisses every overlay.
    var panicKeyEnabled: Bool = true
    /// Dim packed under the blur on the lock screen (0...1).
    var scrimOpacity: Double = 0.45
    /// Number of digits in the passcode (4 or 6).
    var passcodeLength: Int = 4
    /// Cover only the protected app's windows instead of the whole display.
    var coverWindowOnly: Bool = true

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        lockOnAppSwitch = try c.decodeIfPresent(Bool.self, forKey: .lockOnAppSwitch) ?? d.lockOnAppSwitch
        lockOnSleep = try c.decodeIfPresent(Bool.self, forKey: .lockOnSleep) ?? d.lockOnSleep
        lockOnScreenLock = try c.decodeIfPresent(Bool.self, forKey: .lockOnScreenLock) ?? d.lockOnScreenLock
        lockOnIdle = try c.decodeIfPresent(Bool.self, forKey: .lockOnIdle) ?? d.lockOnIdle
        idleTimeout = try c.decodeIfPresent(Double.self, forKey: .idleTimeout) ?? d.idleTimeout
        allowTouchID = try c.decodeIfPresent(Bool.self, forKey: .allowTouchID) ?? d.allowTouchID
        autoPromptTouchID = try c.decodeIfPresent(Bool.self, forKey: .autoPromptTouchID) ?? d.autoPromptTouchID
        showDockIcon = try c.decodeIfPresent(Bool.self, forKey: .showDockIcon) ?? d.showDockIcon
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? d.launchAtLogin
        panicKeyEnabled = try c.decodeIfPresent(Bool.self, forKey: .panicKeyEnabled) ?? d.panicKeyEnabled
        scrimOpacity = try c.decodeIfPresent(Double.self, forKey: .scrimOpacity) ?? d.scrimOpacity
        passcodeLength = try c.decodeIfPresent(Int.self, forKey: .passcodeLength) ?? d.passcodeLength
        coverWindowOnly = try c.decodeIfPresent(Bool.self, forKey: .coverWindowOnly) ?? d.coverWindowOnly
    }
}
