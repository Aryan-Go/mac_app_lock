import AppKit
import Combine

/// Single source of truth for settings and the protected-app list. It is a small
/// JSON document in Application Support, written back whenever either collection
/// changes.
final class Store: ObservableObject {

    @Published var settings: AppSettings {
        didSet { if settings != oldValue { save() } }
    }

    @Published var protectedApps: [ProtectedApp] {
        didSet { save() }
    }

    /// Every user-facing app found on disk, for the picker.
    @Published private(set) var installedApps: [AppInfo] = []
    @Published private(set) var isScanning = false

    private let configURL: URL
    private var loaded = false

    /// `directory` exists so tests can point at a scratch folder instead of the
    /// real Application Support config.
    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AppLock", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        configURL = base.appendingPathComponent("config.json")

        if let data = try? Data(contentsOf: configURL),
           let decoded = try? JSONDecoder().decode(Persisted.self, from: data) {
            settings = decoded.settings
            protectedApps = decoded.protectedApps
        } else {
            settings = AppSettings()
            protectedApps = []
        }
        loaded = true
        refreshInstalledApps()
    }

    // MARK: - Protected apps

    func isProtected(_ bundleID: String) -> Bool {
        protectedApps.contains { $0.bundleID == bundleID }
    }

    /// Whether an app may be protected at all. System UI processes are off
    /// limits so the user can never lock themselves out of the Mac.
    func canProtect(_ bundleID: String) -> Bool {
        !SystemApps.neverLock.contains(bundleID)
            && bundleID != Bundle.main.bundleIdentifier
    }

    func setProtected(_ on: Bool, app: AppInfo) {
        setProtected(on, bundleID: app.bundleID, name: app.name, path: app.path.path)
    }

    func setProtected(_ on: Bool, bundleID: String, name: String, path: String) {
        if on {
            guard canProtect(bundleID) else { return }
            guard !isProtected(bundleID) else { return }
            protectedApps.append(ProtectedApp(bundleID: bundleID, name: name, path: path))
            protectedApps.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } else {
            protectedApps.removeAll { $0.bundleID == bundleID }
        }
    }

    /// Adds an app from a dropped `.app` bundle, discovering its metadata.
    @discardableResult
    func protect(url: URL) -> Bool {
        guard url.pathExtension == "app", let info = InstalledApps.makeInfo(at: url) else { return false }
        if !installedApps.contains(where: { $0.bundleID == info.bundleID }) {
            installedApps.append(info)
            installedApps.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        setProtected(true, app: info)
        return true
    }

    // MARK: - Scanning

    func refreshInstalledApps() {
        guard !isScanning else { return }
        isScanning = true
        DispatchQueue.global(qos: .userInitiated).async {
            let apps = InstalledApps.scan()
            DispatchQueue.main.async {
                self.installedApps = apps
                self.isScanning = false
            }
        }
    }

    // MARK: - Persistence

    private struct Persisted: Codable {
        var settings: AppSettings
        var protectedApps: [ProtectedApp]
    }

    private func save() {
        guard loaded else { return }
        let payload = Persisted(settings: settings, protectedApps: protectedApps)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(payload) else { return }
        try? data.write(to: configURL, options: .atomic)
    }
}
