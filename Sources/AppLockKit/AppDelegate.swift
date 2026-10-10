import AppKit
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {

    private let store = Store()
    private let auth = AuthManager()
    private var controller: AppLockController!
    private var manager: ManagerWindowController!
    private var statusItem: NSStatusItem?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = AppLockController(store: store, auth: auth)
        manager = ManagerWindowController(store: store, auth: auth, controller: controller)

        controller.start()
        installStatusItem()
        applyDockPolicy()

        store.$settings
            .map(\.showDockIcon)
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.applyDockPolicy() }
            .store(in: &cancellables)

        // The system is the source of truth for the login item, so mirror it.
        let launchEnabled = LaunchAtLogin.isEnabled
        if store.settings.launchAtLogin != launchEnabled {
            store.settings.launchAtLogin = launchEnabled
        }

        // First run: nothing to protect yet, or no passcode to protect it with.
        if store.protectedApps.isEmpty || !Passcode.isSet {
            manager.show()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        manager.show()
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        if urls.contains(where: { $0.scheme == "applock" }) {
            manager.show()
        }
    }

    // MARK: - Menu bar

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "lock.shield", accessibilityDescription: "App Lock")
            button.image?.isTemplate = true
        }

        let menu = NSMenu()
        let header = NSMenuItem(title: "App Lock", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        let open = NSMenuItem(title: "Manage Apps…", action: #selector(openManager), keyEquivalent: "o")
        open.target = self
        menu.addItem(open)

        let lockNow = NSMenuItem(title: "Lock Protected Apps Now", action: #selector(lockNow), keyEquivalent: "l")
        lockNow.target = self
        menu.addItem(lockNow)

        menu.addItem(.separator())

        let panic = NSMenuItem(title: "Dismiss Lock Screen (\u{2303}\u{2325}\u{21E7}\u{2318}U)", action: #selector(panic), keyEquivalent: "")
        panic.target = self
        menu.addItem(panic)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit App Lock", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        item.menu = menu
        statusItem = item
    }

    @objc private func openManager() { manager.show() }
    @objc private func lockNow() { controller.lockNow() }
    @objc private func panic() { controller.panic() }
    @objc private func quit() { NSApp.terminate(nil) }

    private func applyDockPolicy() {
        let policy: NSApplication.ActivationPolicy = store.settings.showDockIcon ? .regular : .accessory
        if NSApp.activationPolicy() != policy {
            NSApp.setActivationPolicy(policy)
        }
    }
}
