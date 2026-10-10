import AppKit
import Carbon
import ServiceManagement

/// Processes that must never be lockable. Locking any of these would either
/// break the desktop or trap the user with no way to quit anything.
enum SystemApps {

    static let neverLock: Set<String> = [
        "com.apple.finder",
        "com.apple.dock",
        "com.apple.SystemUIServer",
        "com.apple.WindowServer",
        "com.apple.loginwindow",
        "com.apple.controlcenter",
        "com.apple.notificationcenterui",
        "com.apple.Spotlight",
        "com.apple.screencaptureui",
        "com.apple.SecurityAgent",
        "com.apple.CoreServicesUIAgent",
        "com.apple.ScreenSaver.Engine",
        "com.apple.systempreferences",
        "com.apple.AccessibilityUIServer",
        "com.apple.Siri",
        "com.apple.talagent"
    ]

    /// Apps that *can* be locked but that are worth warning about, because
    /// locking them is an easy way to strand yourself.
    static let caution: Set<String> = [
        "com.apple.Terminal",
        "com.apple.ActivityMonitor",
        "com.apple.dt.Xcode"
    ]
}

/// Fires when the user has been idle past a threshold. Idle time is derived from
/// the oldest of several input event types, which needs no accessibility
/// permission.
final class IdleMonitor {

    var onIdle: (() -> Void)?
    var isEnabled = false
    var timeout: TimeInterval = 300

    private var timer: Timer?
    private var fired = false

    func start() {
        stop()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard isEnabled else { fired = false; return }
        guard systemIdleTime() >= timeout else {
            fired = false
            return
        }
        guard !fired else { return }
        fired = true
        onIdle?()
    }

    private func systemIdleTime() -> TimeInterval {
        let types: [CGEventType] = [
            .mouseMoved, .leftMouseDown, .rightMouseDown, .otherMouseDown,
            .keyDown, .flagsChanged, .scrollWheel, .leftMouseDragged
        ]
        let source = CGEventSourceStateID.combinedSessionState
        var mostRecent = Double.greatestFiniteMagnitude
        for type in types {
            let since = CGEventSource.secondsSinceLastEventType(source, eventType: type)
            mostRecent = min(mostRecent, since)
        }
        return mostRecent == .greatestFiniteMagnitude ? 0 : mostRecent
    }
}

/// Thin wrapper over `SMAppService.mainApp` for the launch-at-login switch.
enum LaunchAtLogin {

    /// `SMAppService` needs a real bundle, so it is a no-op under `swift run`.
    private static var available: Bool { Bundle.main.bundleIdentifier != nil }

    static var isEnabled: Bool {
        guard available else { return false }
        return SMAppService.mainApp.status == .enabled
    }

    @discardableResult
    static func set(_ enabled: Bool) -> Bool {
        guard available else { return false }
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
            return true
        } catch {
            NSLog("AppLock: launch at login failed: \(error.localizedDescription)")
            return false
        }
    }
}

/// Registers a system-wide emergency hotkey. Uses Carbon's hotkey API because it
/// works without the Accessibility permission that an event tap would need.
final class PanicKey {

    var onTrigger: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    private static let signature: OSType = 0x41504C4B // 'APLK'
    private static let keyCode = UInt32(kVK_ANSI_U)
    private static let modifiers = UInt32(cmdKey | optionKey | shiftKey | controlKey)

    var shortcutDescription: String { "⌃⌥⇧⌘U" }

    func register() {
        guard hotKeyRef == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, userData) -> OSStatus in
                guard let event, let userData else { return noErr }
                var hotKeyID = EventHotKeyID()
                GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard hotKeyID.signature == PanicKey.signature else { return noErr }
                let key = Unmanaged<PanicKey>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async { key.onTrigger?() }
                return noErr
            },
            1,
            &eventType,
            selfPointer,
            &handlerRef
        )

        let hotKeyID = EventHotKeyID(signature: PanicKey.signature, id: 1)
        RegisterEventHotKey(
            PanicKey.keyCode,
            PanicKey.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
        if let handlerRef { RemoveEventHandler(handlerRef) }
        handlerRef = nil
    }
}
