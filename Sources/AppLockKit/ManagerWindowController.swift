import AppKit
import Combine
import SwiftUI

/// Owns the single manager window. Closing it keeps AppLock running in the menu
/// bar, so the user can reopen it whenever they want to add or remove apps.
///
/// While a lock screen is up the manager window is hidden and restored
/// afterwards: activating AppLock to take keyboard focus would otherwise raise
/// this window in front of the app being blurred.
final class ManagerWindowController {

    private var window: NSWindow?
    private var wasVisibleBeforeLock = false
    private var cancellables = Set<AnyCancellable>()

    private let store: Store
    private let auth: AuthManager
    private let controller: AppLockController

    init(store: Store, auth: AuthManager, controller: AppLockController) {
        self.store = store
        self.auth = auth
        self.controller = controller

        // Deliberately not `receive(on:)`: the restore must happen synchronously
        // inside the unlock path, before focus is handed back to the app.
        controller.$lockedAppName
            .removeDuplicates()
            .sink { [weak self] lockedName in
                if lockedName == nil {
                    self?.restoreAfterLock()
                } else {
                    self?.suppressForLock()
                }
            }
            .store(in: &cancellables)
    }

    func show() {
        if window == nil {
            let created = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 960, height: 660),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            created.title = "App Lock"
            created.minSize = NSSize(width: 820, height: 560)
            created.isReleasedWhenClosed = false
            created.setFrameAutosaveName("AppLockManagerWindow")
            created.contentView = NSHostingView(
                rootView: ManagerView(store: store, auth: auth, controller: controller)
            )
            created.center()
            window = created
        }

        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Lock suppression

    private func suppressForLock() {
        guard let window, window.isVisible else { return }
        wasVisibleBeforeLock = true
        window.orderOut(nil)
    }

    private func restoreAfterLock() {
        guard wasVisibleBeforeLock else { return }
        wasVisibleBeforeLock = false
        // orderFront, not makeKeyAndOrderFront: focus belongs to the app the user
        // just unlocked, which gets activated immediately after this runs.
        window?.orderFront(nil)
    }
}
