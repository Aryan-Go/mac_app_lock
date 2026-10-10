import AppKit
import Combine

/// Owns the lock state machine: it watches app switches, decides when a
/// protected app must be covered by the lock overlay, and drives authentication.
final class AppLockController: ObservableObject {

    @Published private(set) var lockedAppName: String?
    @Published private(set) var unlockedBundleIDs: Set<String> = []
    /// Bumped whenever the passcode changes so views can refresh.
    @Published private(set) var passcodeVersion = 0

    private let store: Store
    private let auth: AuthManager
    private let overlay = OverlayManager()
    private let monitor = AppMonitor()
    private let idle = IdleMonitor()
    private let hotkey = PanicKey()

    private var cancellables = Set<AnyCancellable>()
    private var systemObservers: [NSObjectProtocol] = []
    private var biometricInFlight = false

    init(store: Store, auth: AuthManager) {
        self.store = store
        self.auth = auth
    }

    // MARK: - Lifecycle

    func start() {
        overlay.model.onSubmit = { [weak self] pin in self?.submit(pin) }
        overlay.model.onBiometricTap = { [weak self] in self?.attemptBiometrics(auto: false) }

        monitor.onActivate = { [weak self] app in self?.handleActivate(app) }
        monitor.onDeactivate = { [weak self] app in self?.handleDeactivate(app) }
        monitor.onTerminate = { [weak self] app in self?.handleTerminate(app) }
        monitor.start()

        idle.onIdle = { [weak self] in self?.idleLock() }
        idle.start()

        hotkey.onTrigger = { [weak self] in self?.panic() }

        observeStore()
        observeSystem()
        applySettings()

        evaluateFrontmost()
    }

    /// Called by the manager when the passcode is set or cleared.
    func passcodeDidChange() {
        passcodeVersion += 1
        unlockedBundleIDs = []
        hideOverlay()
        evaluateFrontmost()
    }

    /// Menu bar action: re-lock every protected app right now.
    func lockNow() {
        unlockedBundleIDs = []
        evaluateFrontmost()
    }

    /// Emergency escape hatch: dismiss every overlay and let the current app
    /// through, so a broken sensor or forgotten passcode never traps the user.
    func panic() {
        if let bundleID = overlay.model.bundleID {
            unlockedBundleIDs.insert(bundleID)
        }
        hideOverlay()
    }

    // MARK: - Monitoring

    private func handleActivate(_ app: NSRunningApplication) {
        guard let bundleID = app.bundleIdentifier else { return }
        switch policy.decisionOnActivate(bundleID: bundleID, isRegularApp: app.activationPolicy == .regular) {
        case .showLock:
            showOverlay(for: app)
        case .hideLock:
            hideOverlay()
        case .ignore:
            break
        }
    }

    private func handleDeactivate(_ app: NSRunningApplication) {
        guard let bundleID = app.bundleIdentifier else { return }
        // Switching away re-arms the lock, which is what makes this an app lock
        // rather than a launch-only gate.
        if policy.shouldReArm(bundleID: bundleID, lockOnAppSwitch: store.settings.lockOnAppSwitch) {
            unlockedBundleIDs.remove(bundleID)
        }
    }

    private func handleTerminate(_ app: NSRunningApplication) {
        guard let bundleID = app.bundleIdentifier else { return }
        unlockedBundleIDs.remove(bundleID)
        if overlay.model.bundleID == bundleID {
            hideOverlay()
        }
    }

    private func evaluateFrontmost() {
        guard let app = monitor.frontmost else { return }
        handleActivate(app)
    }

    // MARK: - Locking

    /// Bundle ids that are protected *and* allowed to be protected.
    private var protectedBundleIDs: Set<String> {
        Set(store.protectedApps.map(\.bundleID).filter { store.canProtect($0) })
    }

    private var policy: LockPolicy {
        LockPolicy(
            protectedBundleIDs: protectedBundleIDs,
            unlockedBundleIDs: unlockedBundleIDs,
            selfBundleID: Bundle.main.bundleIdentifier
        )
    }

    private func isProtected(_ bundleID: String) -> Bool {
        protectedBundleIDs.contains(bundleID)
    }

    private func showOverlay(for app: NSRunningApplication) {
        guard Passcode.isSet, let bundleID = app.bundleIdentifier else { return }
        // Already showing for the same app: keep the current state (including
        // any digits the user has typed).
        if overlay.isVisible && overlay.model.bundleID == bundleID { return }

        auth.refresh()
        biometricInFlight = false

        overlay.model.bundleID = bundleID
        overlay.model.appName = app.localizedName ?? bundleID
        overlay.model.appIcon = app.icon
        overlay.model.scrimOpacity = store.settings.scrimOpacity
        overlay.model.cornerRadius = currentCornerRadius
        overlay.model.showBiometricButton = store.settings.allowTouchID && auth.biometricsAvailable
        overlay.model.biometryLabel = auth.biometryLabel
        overlay.model.reset(passcodeLength: store.settings.passcodeLength)
        overlay.show(targets: targets(for: app)) { [weak self] in
            self?.targets(for: app) ?? []
        }
        // Set before activating: hiding our own windows must happen before
        // activation raises them above the app we are covering.
        lockedAppName = app.localizedName
        overlay.focusApp()

        // Only reach for the sensor on its own if asked. The macOS biometric
        // sheet is a system modal, so popping it on every app switch fights with
        // simply typing the passcode.
        if store.settings.allowTouchID,
           store.settings.autoPromptTouchID,
           auth.biometricsAvailable {
            attemptBiometrics(auto: true)
        }
    }

    /// Where to draw the lock screen: over the app's windows when we can find
    /// them, otherwise over every display.
    private func targets(for app: NSRunningApplication) -> [OverlayTarget] {
        if store.settings.coverWindowOnly {
            let frames = WindowGeometry.onScreenWindowFrames(forPID: app.processIdentifier)
            if !frames.isEmpty {
                return frames.map {
                    OverlayTarget(frame: $0, cornerRadius: WindowGeometry.windowCornerRadius)
                }
            }
        }
        return NSScreen.screens.map { OverlayTarget(frame: $0.frame, cornerRadius: 0) }
    }

    private var currentCornerRadius: CGFloat {
        store.settings.coverWindowOnly ? WindowGeometry.windowCornerRadius : 0
    }

    private func hideOverlay() {
        guard overlay.isVisible else { return }
        overlay.hide()
        lockedAppName = nil
        biometricInFlight = false
    }

    private func idleLock() {
        unlockedBundleIDs = []
        evaluateFrontmost()
    }

    // MARK: - Authentication

    private func submit(_ pin: String) {
        guard let bundleID = overlay.model.bundleID else { return }
        if Passcode.verify(pin) {
            unlock(bundleID)
        } else {
            overlay.model.fail()
        }
    }

    private func attemptBiometrics(auto: Bool) {
        guard let bundleID = overlay.model.bundleID, !biometricInFlight else { return }
        guard store.settings.allowTouchID, auth.biometricsAvailable else { return }
        biometricInFlight = true
        let appName = overlay.model.appName
        let label = auth.biometryLabel

        Task { [weak self] in
            guard let self else { return }
            let outcome = await self.auth.authenticate(reason: "Unlock \(appName)")
            await MainActor.run {
                self.biometricInFlight = false
                switch outcome {
                case .success:
                    self.unlock(bundleID)
                case .cancelled:
                    break
                case .failed:
                    if !auto {
                        self.overlay.model.fail("\(label) failed — enter passcode")
                    }
                }
            }
        }
    }

    private func unlock(_ bundleID: String) {
        unlockedBundleIDs.insert(bundleID)
        if overlay.model.bundleID == bundleID {
            hideOverlay()
        }
        // Hand focus back to the app the user was actually trying to use.
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
            if #available(macOS 14.0, *) {
                app.activate()
            } else {
                app.activate(options: [])
            }
        }
    }

    // MARK: - Settings and system hooks

    private func observeStore() {
        store.$protectedApps
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.reconcile() }
            .store(in: &cancellables)

        store.$settings
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.applySettings()
                self?.reconcile()
            }
            .store(in: &cancellables)
    }

    private func applySettings() {
        idle.timeout = store.settings.idleTimeout
        idle.isEnabled = store.settings.lockOnIdle

        if store.settings.panicKeyEnabled {
            hotkey.register()
        } else {
            hotkey.unregister()
        }

        if overlay.isVisible {
            overlay.model.scrimOpacity = store.settings.scrimOpacity
            overlay.model.cornerRadius = currentCornerRadius
            overlay.model.showBiometricButton = store.settings.allowTouchID && auth.biometricsAvailable
        }
    }

    private func reconcile() {
        if let bundleID = overlay.model.bundleID, !isProtected(bundleID) {
            hideOverlay()
            return
        }
        evaluateFrontmost()
    }

    private func observeSystem() {
        let workspace = NSWorkspace.shared.notificationCenter
        systemObservers.append(workspace.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self, self.store.settings.lockOnSleep else { return }
            self.unlockedBundleIDs = []
            self.hideOverlay()
        })

        systemObservers.append(workspace.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.auth.refresh()
            self.unlockedBundleIDs = []
            self.evaluateFrontmost()
        })

        let distributed = DistributedNotificationCenter.default()
        systemObservers.append(distributed.addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main
        ) { [weak self] _ in
            guard let self, self.store.settings.lockOnScreenLock else { return }
            self.unlockedBundleIDs = []
            self.hideOverlay()
        })
    }
}
