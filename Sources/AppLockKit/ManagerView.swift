import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Lazy icon cache: `NSWorkspace.icon(forFile:)` is not cheap enough to call on
/// every list redraw.
enum AppIcons {
    private static let cache = NSCache<NSString, NSImage>()

    static func icon(for path: String) -> NSImage {
        if let cached = cache.object(forKey: path as NSString) { return cached }
        let icon = NSWorkspace.shared.icon(forFile: path)
        icon.size = NSSize(width: 32, height: 32)
        cache.setObject(icon, forKey: path as NSString)
        return icon
    }
}

struct ManagerView: View {

    @ObservedObject var store: Store
    @ObservedObject var auth: AuthManager
    @ObservedObject var controller: AppLockController

    enum Tab: String, CaseIterable, Identifiable {
        case apps = "Apps"
        case settings = "Settings"
        case about = "About"
        var id: String { rawValue }

        var symbol: String {
            switch self {
            case .apps: return "square.grid.2x2"
            case .settings: return "gearshape"
            case .about: return "info.circle"
            }
        }
    }

    @State private var tab: Tab = .apps

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Divider()
            Group {
                switch tab {
                case .apps: AppsTab(store: store, controller: controller, goToSettings: { tab = .settings })
                case .settings: SettingsTab(store: store, auth: auth, controller: controller)
                case .about: AboutTab()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var tabBar: some View {
        HStack(spacing: 6) {
            ForEach(Tab.allCases) { item in
                Button {
                    tab = item
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: item.symbol)
                        Text(item.rawValue)
                    }
                    .font(.system(size: 13, weight: tab == item ? .semibold : .regular))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(tab == item ? Color.accentColor.opacity(0.16) : Color.clear)
                    )
                    .foregroundStyle(tab == item ? Color.accentColor : Color.primary)
                }
                .buttonStyle(.plain)
            }

            Spacer()

            if let locked = controller.lockedAppName {
                Label("Locked: \(locked)", systemImage: "lock.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.orange)
            } else {
                Label("Watching", systemImage: "eye.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Apps tab

private struct AppsTab: View {

    @ObservedObject var store: Store
    @ObservedObject var controller: AppLockController
    let goToSettings: () -> Void

    enum Filter: String, CaseIterable, Identifiable {
        case all = "All Apps"
        case protected = "Protected"
        var id: String { rawValue }
    }

    @State private var query = ""
    @State private var filter: Filter = .all
    @State private var isDropTargeted = false

    private var passcodeSet: Bool { Passcode.isSet }

    var body: some View {
        VStack(spacing: 0) {
            if !passcodeSet {
                banner
            }
            toolbar
            Divider()
            list
        }
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
        .overlay(alignment: .bottom) {
            if isDropTargeted {
                Text("Drop an app to protect it")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 18)
                    .transition(.opacity)
            }
        }
    }

    private var banner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text("Set a passcode to start locking apps.")
                .font(.system(size: 12))
            Spacer()
            Button("Set Passcode") { goToSettings() }
                .buttonStyle(.link)
                .font(.system(size: 12))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.12))
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search apps", text: $query)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))

            Picker("", selection: $filter) {
                ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 200)

            Button {
                addAppViaPanel()
            } label: {
                Label("Add App…", systemImage: "plus")
            }

            Button {
                store.refreshInstalledApps()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Rescan installed applications")
            .disabled(store.isScanning)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if store.isScanning && store.installedApps.isEmpty {
                    ProgressView("Scanning applications…")
                        .padding(40)
                }

                ForEach(visibleApps) { app in
                    AppRow(app: app, store: store)
                    Divider().padding(.leading, 56)
                }

                let missing = missingProtectedApps
                if !missing.isEmpty {
                    sectionHeader("Protected, but not found on disk")
                    ForEach(missing) { app in
                        MissingRow(app: app, store: store)
                        Divider().padding(.leading, 56)
                    }
                }
            }
        }
    }

    private var visibleApps: [AppInfo] {
        let base = query.isEmpty
            ? store.installedApps
            : store.installedApps.filter {
                $0.name.localizedCaseInsensitiveContains(query)
                    || $0.bundleID.localizedCaseInsensitiveContains(query)
            }
        switch filter {
        case .all: return base
        case .protected: return base.filter { store.isProtected($0.bundleID) }
        }
    }

    private var missingProtectedApps: [ProtectedApp] {
        store.protectedApps.filter { protected in
            !store.installedApps.contains { $0.bundleID == protected.bundleID }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 6)
    }

    // MARK: - Adding apps

    private func addAppViaPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Protect"
        if panel.runModal() == .OK {
            panel.urls.forEach { _ = store.protect(url: $0) }
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            handled = true
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                var url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else if let direct = item as? URL {
                    url = direct
                }
                guard let url else { return }
                DispatchQueue.main.async { _ = store.protect(url: url) }
            }
        }
        return handled
    }
}

private struct AppRow: View {
    let app: AppInfo
    @ObservedObject var store: Store

    private var isProtected: Bool { store.isProtected(app.bundleID) }
    private var isCaution: Bool { SystemApps.caution.contains(app.bundleID) }

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: AppIcons.icon(for: app.path.path))
                .resizable()
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(app.name).font(.system(size: 13, weight: .medium))
                    if isCaution {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.orange)
                            .help("Locking this app can strand you — AppLock itself may need to be quit from here.")
                    }
                }
                Text(app.path.path)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            Toggle("", isOn: Binding(
                get: { isProtected },
                set: { store.setProtected($0, app: app) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

private struct MissingRow: View {
    let app: ProtectedApp
    @ObservedObject var store: Store

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: AppIcons.icon(for: app.path))
                .resizable()
                .frame(width: 32, height: 32)
                .opacity(0.4)
            VStack(alignment: .leading, spacing: 2) {
                Text(app.name).font(.system(size: 13, weight: .medium))
                Text(app.bundleID).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            Text("Not found")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Toggle("", isOn: Binding(
                get: { true },
                set: { if !$0 { store.setProtected(false, bundleID: app.bundleID, name: app.name, path: app.path) } }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

// MARK: - Settings tab

private struct SettingsTab: View {

    @ObservedObject var store: Store
    @ObservedObject var auth: AuthManager
    @ObservedObject var controller: AppLockController

    @State private var showingPasscodeSheet = false
    @State private var passcodeRefresh = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                passcodeCard
                lockingCard
                unlockCard
                appearanceCard
                generalCard
                aboutPanicCard
            }
            .padding(20)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .sheet(isPresented: $showingPasscodeSheet) {
            PasscodeSheet { pin, length in
                Passcode.set(pin)
                store.settings.passcodeLength = length
                controller.passcodeDidChange()
                passcodeRefresh += 1
            }
        }
        .id(passcodeRefresh)
    }

    private var passcodeCard: some View {
        Card(title: "Passcode") {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Passcode.isSet ? "Passcode is set (\(store.settings.passcodeLength) digits)" : "No passcode set")
                        .font(.system(size: 13, weight: .medium))
                    Text("Apps are only locked once a passcode exists.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if Passcode.isSet {
                    Button("Remove") {
                        Passcode.clear()
                        controller.passcodeDidChange()
                        passcodeRefresh += 1
                    }
                }
                Button(Passcode.isSet ? "Change Passcode" : "Set Passcode") {
                    showingPasscodeSheet = true
                }
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var lockingCard: some View {
        Card(title: "When to lock") {
            VStack(alignment: .leading, spacing: 14) {
                SettingToggle(
                    title: "Lock when I switch away",
                    subtitle: "The app re-locks as soon as you leave it, so every return needs auth again.",
                    isOn: $store.settings.lockOnAppSwitch
                )
                SettingToggle(
                    title: "Lock on sleep",
                    subtitle: "Re-arm every protected app when the Mac goes to sleep.",
                    isOn: $store.settings.lockOnSleep
                )
                SettingToggle(
                    title: "Lock when the screen locks",
                    subtitle: "Unlock requirements reset when you unlock the Mac.",
                    isOn: $store.settings.lockOnScreenLock
                )
                SettingToggle(
                    title: "Lock after idle",
                    subtitle: "Re-lock in place after a stretch of no input.",
                    isOn: $store.settings.lockOnIdle
                )
                if store.settings.lockOnIdle {
                    HStack(spacing: 12) {
                        Text("Idle for")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Slider(value: $store.settings.idleTimeout, in: 30...1800, step: 30)
                        Text("\(Int(store.settings.idleTimeout / 60)) min")
                            .font(.system(size: 12, design: .monospaced))
                            .frame(width: 58, alignment: .trailing)
                    }
                }
            }
        }
    }

    private var unlockCard: some View {
        Card(title: "How to unlock") {
            VStack(alignment: .leading, spacing: 14) {
                SettingToggle(
                    title: "Allow \(auth.biometryLabel)",
                    subtitle: auth.biometricsAvailable
                        ? "Shows an Unlock with \(auth.biometryLabel) button on the lock screen."
                        : "No biometric sensor detected on this Mac.",
                    isOn: $store.settings.allowTouchID
                )
                SettingToggle(
                    title: "Ask for \(auth.biometryLabel) automatically",
                    subtitle: "Pops the system biometric prompt the moment an app locks. Off means you tap the button when you want it.",
                    isOn: $store.settings.autoPromptTouchID
                )
                .disabled(!store.settings.allowTouchID)
                .opacity(store.settings.allowTouchID ? 1 : 0.5)
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Passcode length")
                        Text("Used for both entry and setup.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker("", selection: $store.settings.passcodeLength) {
                        Text("4 digits").tag(4)
                        Text("6 digits").tag(6)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 190)
                }
            }
        }
    }

    private var appearanceCard: some View {
        Card(title: "Overlay") {
            VStack(alignment: .leading, spacing: 14) {
                SettingToggle(
                    title: "Cover only the app's window",
                    subtitle: "Off covers the whole display, like a phone lock screen.",
                    isOn: $store.settings.coverWindowOnly
                )
                HStack(spacing: 12) {
                    Text("Darkness")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Slider(value: $store.settings.scrimOpacity, in: 0...0.85)
                    Text("\(Int(store.settings.scrimOpacity * 100))%")
                        .font(.system(size: 12, design: .monospaced))
                        .frame(width: 46, alignment: .trailing)
                }
            }
        }
    }

    private var generalCard: some View {
        Card(title: "General") {
            VStack(alignment: .leading, spacing: 14) {
                SettingToggle(
                    title: "Show Dock icon",
                    subtitle: "Off keeps AppLock in the menu bar only.",
                    isOn: $store.settings.showDockIcon
                )
                SettingToggle(
                    title: "Launch at login",
                    subtitle: "Start AppLock automatically the next time you log in.",
                    isOn: Binding(
                        get: { store.settings.launchAtLogin },
                        set: { store.settings.launchAtLogin = $0; LaunchAtLogin.set($0) }
                    )
                )
            }
        }
    }

    private var aboutPanicCard: some View {
        Card(title: "Safety") {
            VStack(alignment: .leading, spacing: 14) {
                SettingToggle(
                    title: "Emergency hotkey",
                    subtitle: "Press \u{2303}\u{2325}\u{21E7}\u{2318}U anywhere to dismiss the lock screen instantly.",
                    isOn: $store.settings.panicKeyEnabled
                )
            }
        }
    }
}

// MARK: - About tab

private struct AboutTab: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Label("App Lock", systemImage: "lock.shield.fill")
                        .font(.system(size: 22, weight: .semibold))
                    Text("A focus-driven app locker for the Mac. Protected apps are covered by a blurred, iPhone-style lock screen the moment they come forward, and re-locked the moment you switch away.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Card(title: "How it works") {
                    VStack(alignment: .leading, spacing: 8) {
                        bullet("Watches which app becomes frontmost via the workspace notification centre.")
                        bullet("Finds the app's windows and covers exactly those, with a blur of what is underneath — no screen recording or accessibility permission needed.")
                        bullet("Holds the keyboard so the covered app never sees keystrokes; you type the passcode straight in, and only Cmd+Tab passes through.")
                        bullet("Verifies your passcode (salted SHA-256, stored in the Keychain) or Touch ID.")
                        bullet("Re-locks on app switch, sleep, screen lock and idle as configured.")
                    }
                }

                Card(title: "Emergency") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Dismiss any lock screen: \u{2303}\u{2325}\u{21E7}\u{2318}U")
                        Text("The menu bar icon can also re-lock everything or quit AppLock.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .font(.system(size: 13))
                }

                HStack {
                    Spacer()
                    Button("Quit App Lock") { NSApp.terminate(nil) }
                }
            }
            .padding(20)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "circle.fill").font(.system(size: 5)).padding(.top, 6)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Passcode sheet

private struct PasscodeSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onSave: (String, Int) -> Void

    @State private var first = ""
    @State private var second = ""
    @State private var length = Passcode.isSet ? 4 : 4
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Set Passcode").font(.system(size: 16, weight: .semibold))

            Picker("Digits", selection: $length) {
                Text("4 digits").tag(4)
                Text("6 digits").tag(6)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            SecureField("Enter passcode", text: $first)
            SecureField("Confirm passcode", text: $second)

            if let error {
                Text(error).font(.system(size: 12)).foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") { save() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 360)
    }

    private func save() {
        let digits = first.filter(\.isNumber)
        guard digits.count == length else {
            error = "Passcode must be exactly \(length) digits."
            return
        }
        guard digits == second else {
            error = "The two passcodes do not match."
            return
        }
        onSave(digits, length)
        dismiss()
    }
}
