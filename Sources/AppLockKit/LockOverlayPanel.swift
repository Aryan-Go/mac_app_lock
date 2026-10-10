import AppKit
import SwiftUI

/// Observable state for the lock screen: the app being covered, the digits typed
/// so far, the error message and the biometric option.
final class LockOverlayModel: ObservableObject {

    @Published var appName = ""
    @Published var appIcon: NSImage?
    @Published var passcodeLength = 4
    @Published var enteredCount = 0
    @Published var shakeTrigger: CGFloat = 0
    @Published var message: String?
    @Published var showBiometricButton = false
    @Published var biometryLabel = "Touch ID"
    @Published var scrimOpacity: Double = 0.45
    @Published var cornerRadius: CGFloat = 0

    var bundleID: String?
    var onSubmit: ((String) -> Void)?
    var onBiometricTap: (() -> Void)?

    private var buffer = ""

    func reset(passcodeLength: Int) {
        buffer = ""
        enteredCount = 0
        message = nil
        shakeTrigger = 0
        self.passcodeLength = passcodeLength
    }

    func append(_ digit: String) {
        guard buffer.count < passcodeLength else { return }
        buffer.append(digit)
        enteredCount = buffer.count
        message = nil
        Haptics.tap()

        guard buffer.count == passcodeLength else { return }
        let pin = buffer
        buffer = ""
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.09) { [weak self] in
            self?.enteredCount = 0
            self?.onSubmit?(pin)
        }
    }

    func delete() {
        guard !buffer.isEmpty else { return }
        buffer.removeLast()
        enteredCount = buffer.count
        message = nil
    }

    func fail(_ text: String = "Incorrect passcode") {
        message = text
        Haptics.warning()
        shakeTrigger += 1
    }
}

/// Where an overlay panel should sit, and how round its corners should be.
struct OverlayTarget: Equatable {
    var frame: CGRect
    var cornerRadius: CGFloat
}

/// One lock screen, sized to a single window of the protected app.
///
/// The panel carries a behind-window blur so the app underneath is frosted, plus
/// the SwiftUI lock screen on top. It sits above everything, on every Space, and
/// survives full-screen apps.
final class LockOverlayPanel: NSPanel {

    private let effect = NSVisualEffectView()
    private let host: NSHostingView<LockOverlayView>

    init(model: LockOverlayModel) {
        host = NSHostingView(rootView: LockOverlayView(model: model))

        super.init(
            contentRect: .zero,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = false
        hasShadow = false
        isOpaque = false
        backgroundColor = .clear
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        hidesOnDeactivate = false
        isMovable = false
        acceptsMouseMovedEvents = true
        animationBehavior = .none

        // The blur lives in its own subview rather than being the content view, so
        // rounding its corners cannot interfere with the backdrop sampling.
        let container = NSView(frame: .zero)
        container.autoresizingMask = [.width, .height]
        contentView = container

        effect.blendingMode = .behindWindow
        effect.material = .fullScreenUI
        effect.state = .active
        effect.appearance = NSAppearance(named: .vibrantDark)
        effect.wantsLayer = true
        effect.autoresizingMask = [.width, .height]
        container.addSubview(effect)

        host.autoresizingMask = [.width, .height]
        container.addSubview(host)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Moves and resizes the panel to cover `target`.
    func configure(with target: OverlayTarget) {
        setFrame(target.frame, display: true)

        let bounds = NSRect(origin: .zero, size: target.frame.size)
        effect.frame = bounds
        host.frame = bounds
        effect.layer?.cornerRadius = target.cornerRadius
        effect.layer?.masksToBounds = target.cornerRadius > 0
    }
}

/// Creates, positions and repositions the overlay panels, and captures
/// keystrokes so the covered app never sees them.
final class OverlayManager {

    let model = LockOverlayModel()
    private(set) var isVisible = false

    private var panels: [LockOverlayPanel] = []
    private var currentTargets: [OverlayTarget] = []
    private var keyMonitor: Any?
    private var repositionTimer: Timer?
    private var provider: (() -> [OverlayTarget])?

    // MARK: - Show and hide

    /// `provider` is polled while locked so the overlay follows a window that the
    /// app resizes or moves itself.
    func show(targets: [OverlayTarget], provider: (() -> [OverlayTarget])?) {
        isVisible = true
        self.provider = provider
        apply(targets)
        installKeyMonitor()
        startRepositioning()
    }

    func hide() {
        guard isVisible else { return }
        isVisible = false
        provider = nil
        stopRepositioning()
        removeKeyMonitor()
        panels.forEach { $0.orderOut(nil) }
        panels.forEach { $0.resignKey() }
    }

    /// Brings the overlay forward and activates the app so typed digits and the
    /// biometric prompt behave like a normal front window.
    func focusApp() {
        guard isVisible, !panels.isEmpty else { return }
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        let mouse = NSEvent.mouseLocation
        let keyPanel = panels.first { $0.frame.contains(mouse) } ?? panels[0]
        panels.forEach { $0.orderFrontRegardless() }
        keyPanel.makeKeyAndOrderFront(nil)
    }

    // MARK: - Panels

    private func apply(_ targets: [OverlayTarget]) {
        guard isVisible, !targets.isEmpty else { return }
        currentTargets = targets

        // Panels are pooled: re-locking a second time has no first-paint flash.
        while panels.count < targets.count {
            panels.append(LockOverlayPanel(model: model))
        }
        while panels.count > targets.count {
            panels.removeLast().orderOut(nil)
        }

        for (panel, target) in zip(panels, targets) {
            panel.configure(with: target)
            panel.orderFrontRegardless()
        }
    }

    private func startRepositioning() {
        repositionTimer?.invalidate()
        repositionTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self, self.isVisible, let provider = self.provider else { return }
            let targets = provider()
            guard !targets.isEmpty, targets != self.currentTargets else { return }
            self.apply(targets)
        }
    }

    private func stopRepositioning() {
        repositionTimer?.invalidate()
        repositionTimer = nil
    }

    // MARK: - Keyboard

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isVisible else { return event }
            return self.handleKey(event) ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = nil
    }

    /// Returns true when the event was consumed. Digits and delete drive the
    /// passcode field; Cmd+Tab still works; everything else is swallowed so the
    /// app beneath the overlay cannot be driven by the keyboard.
    private func handleKey(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 48: // Tab — allow Cmd+Tab to switch away
            return false
        case 51, 117: // Delete / forward delete
            model.delete()
            return true
        case 53: // Escape — swallowed on purpose
            return true
        default:
            break
        }

        if let characters = event.charactersIgnoringModifiers,
           let first = characters.first,
           first.isNumber {
            model.append(String(first))
            return true
        }
        return true
    }
}
