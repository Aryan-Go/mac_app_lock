import AppKit

/// The library entry point. The executable target is a three-line wrapper around
/// this, which keeps all logic testable.
public enum AppLockKit {

    /// Retained for the lifetime of the process: `NSApplication.delegate` is a
    /// weak reference.
    private static var delegate: AppDelegate?

    public static func run() {
        // Single instance: if AppLock is already running, surface it instead of
        // starting a second copy that would fight over the overlay.
        if let identifier = Bundle.main.bundleIdentifier {
            let others = NSRunningApplication
                .runningApplications(withBundleIdentifier: identifier)
                .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
            if let existing = others.first {
                if #available(macOS 14.0, *) {
                    existing.activate()
                } else {
                    existing.activate(options: [])
                }
                exit(0)
            }
        }

        let application = NSApplication.shared
        let delegate = AppDelegate()
        Self.delegate = delegate
        application.delegate = delegate
        application.setActivationPolicy(.regular)
        application.run()
    }
}
