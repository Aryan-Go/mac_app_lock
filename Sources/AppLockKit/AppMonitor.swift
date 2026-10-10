import AppKit

/// Watches the workspace for app activation, deactivation and termination.
/// Everything is delivered on the main thread via the main queue.
final class AppMonitor {

    var onActivate: ((NSRunningApplication) -> Void)?
    var onDeactivate: ((NSRunningApplication) -> Void)?
    var onTerminate: ((NSRunningApplication) -> Void)?

    private var observers: [NSObjectProtocol] = []

    func start() {
        observe(NSWorkspace.didActivateApplicationNotification) { [weak self] app in
            self?.onActivate?(app)
        }
        observe(NSWorkspace.didDeactivateApplicationNotification) { [weak self] app in
            self?.onDeactivate?(app)
        }
        observe(NSWorkspace.didTerminateApplicationNotification) { [weak self] app in
            self?.onTerminate?(app)
        }
    }

    func stop() {
        let center = NSWorkspace.shared.notificationCenter
        observers.forEach { center.removeObserver($0) }
        observers.removeAll()
    }

    var frontmost: NSRunningApplication? {
        NSWorkspace.shared.frontmostApplication
    }

    private func observe(
        _ name: Notification.Name,
        handler: @escaping (NSRunningApplication) -> Void
    ) {
        let token = NSWorkspace.shared.notificationCenter.addObserver(
            forName: name,
            object: nil,
            queue: .main
        ) { note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }
            handler(app)
        }
        observers.append(token)
    }
}
