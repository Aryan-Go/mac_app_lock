import AppKit

/// Scans the usual application locations so the picker can show everything the
/// user might want to protect. Runs off the main thread because reading a few
/// hundred bundles (and their icons) is not instant.
enum InstalledApps {

    private static let searchDirectories: [String] = [
        "/Applications",
        "/Applications/Utilities",
        "/System/Applications",
        "/System/Applications/Utilities",
        "/System/Library/CoreServices"
    ]

    static func scan() -> [AppInfo] {
        var roots = searchDirectories.map { URL(fileURLWithPath: $0, isDirectory: true) }
        if let home = FileManager.default.urls(for: .applicationDirectory, in: .userDomainMask).first {
            roots.append(home)
        }

        var seen = Set<String>()
        var result: [AppInfo] = []

        for root in roots {
            guard let entries = try? FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }

            for url in entries where url.pathExtension == "app" {
                guard let info = makeInfo(at: url) else { continue }
                guard seen.insert(info.bundleID).inserted else { continue }
                result.append(info)
            }
        }

        return result.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    /// Builds an `AppInfo` for a single bundle, returning nil when it is not a
    /// user-facing app (no bundle id, background-only, or an AppLock helper).
    static func makeInfo(at url: URL) -> AppInfo? {
        guard let bundle = Bundle(url: url) else { return nil }
        guard let bundleID = bundle.bundleIdentifier, !bundleID.isEmpty else { return nil }
        guard bundleID != Bundle.main.bundleIdentifier else { return nil }

        let info = bundle.infoDictionary ?? [:]

        // Skip background-only processes and menu-bar-only helpers: they never
        // present a window worth locking.
        if (info["LSBackgroundOnly"] as? Bool) == true { return nil }
        if (info["LSUIElement"] as? Bool) == true { return nil }

        let name = (info["CFBundleDisplayName"] as? String)
            ?? (info["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent

        return AppInfo(bundleID: bundleID, name: name, path: url)
    }
}
