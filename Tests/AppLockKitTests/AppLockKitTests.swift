import Security
import XCTest
@testable import AppLockKit

final class PasscodeStoreTests: XCTestCase {

    private let store = PasscodeStore(service: "com.aryan.applock.tests")

    override func setUp() {
        super.setUp()
        store.clear()
    }

    override func tearDown() {
        store.clear()
        super.tearDown()
    }

    func testEmptyStoreRejectsEverything() {
        XCTAssertFalse(store.isSet)
        XCTAssertFalse(store.verify("1234"))
    }

    func testSetAndVerify() {
        store.set("1234")
        XCTAssertTrue(store.isSet)
        XCTAssertTrue(store.verify("1234"))
        XCTAssertFalse(store.verify("1235"))
        XCTAssertFalse(store.verify(""))
        XCTAssertFalse(store.verify("12345"))
    }

    func testSixDigitPasscode() {
        store.set("654321")
        XCTAssertTrue(store.verify("654321"))
        XCTAssertFalse(store.verify("65432"))
        XCTAssertFalse(store.verify("6543210"))
    }

    func testReplacingPasscodeInvalidatesTheOldOne() {
        store.set("1111")
        store.set("2222")
        XCTAssertFalse(store.verify("1111"))
        XCTAssertTrue(store.verify("2222"))
    }

    func testClearRemovesPasscode() {
        store.set("0000")
        store.clear()
        XCTAssertFalse(store.isSet)
        XCTAssertFalse(store.verify("0000"))
    }

    /// The stored payload must be a hex salt plus a hex SHA-256 digest, never the
    /// passcode itself.
    func testStoredPayloadIsSaltedHashNotPlaintext() throws {
        store.set("1234")

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.aryan.applock.tests",
            kSecAttrAccount as String: "passcode",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        XCTAssertEqual(SecItemCopyMatching(query as CFDictionary, &item), errSecSuccess)

        let raw = try XCTUnwrap(item as? Data)
        let text = try XCTUnwrap(String(data: raw, encoding: .utf8))

        XCTAssertFalse(text.contains("1234"), "plaintext passcode must never be stored")
        let parts = text.split(separator: "$")
        XCTAssertEqual(parts.count, 2, "expected salt$hash format")
        XCTAssertEqual(parts[0].count, 32, "16-byte salt as hex")
        XCTAssertEqual(parts[1].count, 64, "32-byte SHA-256 as hex")
    }

    /// The same passcode stored twice must produce different payloads, proving
    /// the salt is random.
    func testSaltIsRandom() {
        store.set("1234")
        let first = storedPayload()
        store.set("1234")
        let second = storedPayload()
        XCTAssertNotEqual(first, second)
    }

    private func storedPayload() -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.aryan.applock.tests",
            kSecAttrAccount as String: "passcode",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
}

final class AppSettingsTests: XCTestCase {

    func testDecodingEmptyObjectYieldsDefaults() throws {
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        XCTAssertTrue(settings.lockOnAppSwitch)
        XCTAssertTrue(settings.lockOnSleep)
        XCTAssertTrue(settings.lockOnScreenLock)
        XCTAssertFalse(settings.lockOnIdle)
        XCTAssertEqual(settings.idleTimeout, 300)
        XCTAssertTrue(settings.allowTouchID)
        XCTAssertTrue(settings.showDockIcon)
        XCTAssertTrue(settings.panicKeyEnabled)
        XCTAssertEqual(settings.scrimOpacity, 0.45, accuracy: 0.0001)
        XCTAssertEqual(settings.passcodeLength, 4)
        XCTAssertTrue(settings.coverWindowOnly)
        XCTAssertFalse(settings.autoPromptTouchID, "the biometric sheet should be opt-in")
    }

    /// Config files written by an older build must not break when a key is added.
    func testDecodingPartialObjectKeepsKnownValues() throws {
        let json = Data(#"{"passcodeLength": 6, "lockOnIdle": true}"#.utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: json)
        XCTAssertEqual(settings.passcodeLength, 6)
        XCTAssertTrue(settings.lockOnIdle)
        XCTAssertTrue(settings.lockOnAppSwitch, "missing keys fall back to defaults")
    }

    func testRoundTrip() throws {
        var settings = AppSettings()
        settings.lockOnIdle = true
        settings.idleTimeout = 120
        settings.passcodeLength = 6
        settings.showDockIcon = false
        settings.scrimOpacity = 0.7

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertEqual(decoded, settings)
    }
}

final class StoreTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppLockTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testProtectSurvivesReload() {
        let store = Store(directory: directory)
        XCTAssertTrue(store.protectedApps.isEmpty)

        store.setProtected(true, bundleID: "com.example.demo", name: "Demo", path: "/Applications/Demo.app")
        XCTAssertTrue(store.isProtected("com.example.demo"))

        let reloaded = Store(directory: directory)
        XCTAssertEqual(reloaded.protectedApps.map(\.bundleID), ["com.example.demo"])
        XCTAssertEqual(reloaded.protectedApps.first?.name, "Demo")
    }

    func testUnprotectRemovesAndPersists() {
        let store = Store(directory: directory)
        store.setProtected(true, bundleID: "com.example.demo", name: "Demo", path: "/Applications/Demo.app")
        store.setProtected(false, bundleID: "com.example.demo", name: "Demo", path: "/Applications/Demo.app")

        XCTAssertFalse(store.isProtected("com.example.demo"))
        XCTAssertTrue(Store(directory: directory).protectedApps.isEmpty)
    }

    func testSystemAppsCannotBeProtected() {
        let store = Store(directory: directory)
        store.setProtected(true, bundleID: "com.apple.finder", name: "Finder", path: "/System/Library/CoreServices/Finder.app")

        XCTAssertFalse(store.canProtect("com.apple.finder"))
        XCTAssertFalse(store.isProtected("com.apple.finder"))
        XCTAssertTrue(store.protectedApps.isEmpty)
    }

    func testProtectingTwiceDoesNotDuplicate() {
        let store = Store(directory: directory)
        for _ in 0..<2 {
            store.setProtected(true, bundleID: "com.example.demo", name: "Demo", path: "/Applications/Demo.app")
        }
        XCTAssertEqual(store.protectedApps.count, 1)
    }

    func testProtectURLRejectsNonAppBundle() {
        let store = Store(directory: directory)
        XCTAssertFalse(store.protect(url: URL(fileURLWithPath: "/etc/hosts")))
    }

    func testSettingsPersistAcrossReload() {
        let store = Store(directory: directory)
        store.settings.passcodeLength = 6
        store.settings.lockOnIdle = true

        let reloaded = Store(directory: directory)
        XCTAssertEqual(reloaded.settings.passcodeLength, 6)
        XCTAssertTrue(reloaded.settings.lockOnIdle)
    }
}

final class InstalledAppsTests: XCTestCase {

    func testScanFindsRealAppsWithUniqueBundleIDs() {
        let apps = InstalledApps.scan()
        XCTAssertFalse(apps.isEmpty, "expected to find apps in /Applications or /System/Applications")
        XCTAssertTrue(apps.allSatisfy { !$0.bundleID.isEmpty })
        XCTAssertEqual(Set(apps.map(\.bundleID)).count, apps.count, "bundle ids must be unique")
        XCTAssertEqual(apps, apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
    }

    func testMakeInfoRejectsNonBundle() {
        XCTAssertNil(InstalledApps.makeInfo(at: URL(fileURLWithPath: "/etc/hosts")))
    }

    func testNeverLockContainsSystemUI() {
        XCTAssertTrue(SystemApps.neverLock.contains("com.apple.finder"))
        XCTAssertTrue(SystemApps.neverLock.contains("com.apple.dock"))
        XCTAssertTrue(SystemApps.neverLock.contains("com.apple.SystemUIServer"))
    }
}

final class WindowGeometryTests: XCTestCase {

    /// CG window bounds are top-left origin; Cocoa is bottom-left.
    func testCocoaRectFlipsYAgainstPrimaryHeight() {
        let cg = CGRect(x: 100, y: 50, width: 800, height: 600)
        XCTAssertEqual(
            WindowGeometry.cocoaRect(fromCG: cg, primaryHeight: 1000),
            CGRect(x: 100, y: 350, width: 800, height: 600)
        )
    }

    func testWindowAtTopOfScreenMapsToTopInCocoa() {
        let cg = CGRect(x: 0, y: 0, width: 500, height: 400)
        XCTAssertEqual(WindowGeometry.cocoaRect(fromCG: cg, primaryHeight: 1000).maxY, 1000)
    }

    func testWindowAtBottomOfScreenMapsToOrigin() {
        let cg = CGRect(x: 20, y: 700, width: 500, height: 300)
        XCTAssertEqual(WindowGeometry.cocoaRect(fromCG: cg, primaryHeight: 1000).minY, 0)
    }

    func testUnknownProcessHasNoWindows() {
        XCTAssertTrue(WindowGeometry.onScreenWindowFrames(forPID: 999_999).isEmpty)
    }

    /// Brave/VS Code/Ghostty style: chrome reported as several stacked strips.
    /// They must collapse into the single window they belong to.
    func testClusteringMergesStackedSubWindows() {
        let strips = [
            CGRect(x: 100, y: 100, width: 800, height: 40),
            CGRect(x: 100, y: 140, width: 800, height: 75),
            CGRect(x: 100, y: 100, width: 800, height: 151),
            CGRect(x: 100, y: 215, width: 800, height: 500)
        ]
        let merged = WindowGeometry.cluster(strips)
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0], CGRect(x: 100, y: 100, width: 800, height: 615))
    }

    func testClusteringKeepsFarApartWindowsSeparate() {
        let left = CGRect(x: 0, y: 0, width: 400, height: 300)
        let right = CGRect(x: 900, y: 0, width: 400, height: 300)
        let merged = WindowGeometry.cluster([left, right])
        XCTAssertEqual(merged.count, 2)
        XCTAssertTrue(merged.contains(left))
        XCTAssertTrue(merged.contains(right))
    }

    func testClusteringOverlappingWindowsUnionsThem() {
        let a = CGRect(x: 0, y: 0, width: 400, height: 300)
        let b = CGRect(x: 200, y: 100, width: 400, height: 300)
        let merged = WindowGeometry.cluster([a, b])
        XCTAssertEqual(merged, [CGRect(x: 0, y: 0, width: 600, height: 400)])
    }

    func testClusteringEmptyInput() {
        XCTAssertTrue(WindowGeometry.cluster([]).isEmpty)
    }

    func testSubstantialRegionsWinOverStrayHUDs() {
        let window = CGRect(x: 0, y: 0, width: 800, height: 600)
        let hud = CGRect(x: 900, y: 0, width: 120, height: 90)
        XCTAssertEqual(WindowGeometry.coverableRegions(from: [window, hud]), [window])
    }

    /// An app whose only window is small must still be covered, rather than the
    /// overlay falling back to the entire display.
    func testSmallWindowStillCovered() {
        let small = CGRect(x: 0, y: 0, width: 120, height: 90)
        XCTAssertEqual(WindowGeometry.coverableRegions(from: [small]), [small])
    }

    func testNoFramesMeansNoRegions() {
        XCTAssertTrue(WindowGeometry.coverableRegions(from: []).isEmpty)
    }
}

final class LockPolicyTests: XCTestCase {

    private func policy(protected: [String], unlocked: [String] = []) -> LockPolicy {
        LockPolicy(
            protectedBundleIDs: Set(protected),
            unlockedBundleIDs: Set(unlocked),
            selfBundleID: "com.aryan.applock"
        )
    }

    func testProtectedAppLocksOnFirstFocus() {
        XCTAssertEqual(
            policy(protected: ["com.a"]).decisionOnActivate(bundleID: "com.a", isRegularApp: true),
            .showLock
        )
    }

    func testUnlockedProtectedAppDoesNotRelock() {
        XCTAssertEqual(
            policy(protected: ["com.a"], unlocked: ["com.a"]).decisionOnActivate(bundleID: "com.a", isRegularApp: true),
            .hideLock
        )
    }

    func testSwitchingToAnotherRegularAppHidesOverlay() {
        XCTAssertEqual(
            policy(protected: ["com.a"]).decisionOnActivate(bundleID: "com.b", isRegularApp: true),
            .hideLock
        )
    }

    func testBackgroundAgentActivationIsIgnored() {
        XCTAssertEqual(
            policy(protected: ["com.a"]).decisionOnActivate(bundleID: "com.apple.SecurityAgent", isRegularApp: false),
            .ignore
        )
    }

    func testOwnActivationIsIgnored() {
        XCTAssertEqual(
            policy(protected: ["com.a"]).decisionOnActivate(bundleID: "com.aryan.applock", isRegularApp: true),
            .ignore
        )
    }

    func testSwitchingAwayReArmsOnlyWhenEnabled() {
        let p = policy(protected: ["com.a"])
        XCTAssertTrue(p.shouldReArm(bundleID: "com.a", lockOnAppSwitch: true))
        XCTAssertFalse(p.shouldReArm(bundleID: "com.a", lockOnAppSwitch: false))
        XCTAssertFalse(p.shouldReArm(bundleID: "com.b", lockOnAppSwitch: true))
    }

    /// The full round trip the user asked for: focus the app, authenticate, leave,
    /// come back and be asked again.
    func testLockUnlockRelockCycle() {
        let bundle = "com.a"
        var unlocked: Set<String> = []

        func decide() -> LockPolicy.Decision {
            LockPolicy(protectedBundleIDs: [bundle], unlockedBundleIDs: unlocked, selfBundleID: nil)
                .decisionOnActivate(bundleID: bundle, isRegularApp: true)
        }

        XCTAssertEqual(decide(), .showLock, "first focus should lock")

        unlocked.insert(bundle) // user authenticated
        XCTAssertEqual(decide(), .hideLock)

        // User switches away — deactivation re-arms the lock.
        let reArm = LockPolicy(protectedBundleIDs: [bundle], unlockedBundleIDs: unlocked, selfBundleID: nil)
            .shouldReArm(bundleID: bundle, lockOnAppSwitch: true)
        XCTAssertTrue(reArm)
        unlocked.remove(bundle)

        XCTAssertEqual(decide(), .showLock, "returning should require auth again")
    }
}

