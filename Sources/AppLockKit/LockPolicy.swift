/// The pure part of the lock decision, split out from `AppLockController` so the
/// rule can be tested without ever creating a real overlay.
struct LockPolicy {

    enum Decision: Equatable {
        /// Cover the app: it is protected and not authenticated yet.
        case showLock
        /// Take the overlay down.
        case hideLock
        /// Not our business — leave the lock state alone.
        case ignore
    }

    let protectedBundleIDs: Set<String>
    let unlockedBundleIDs: Set<String>
    let selfBundleID: String?

    /// Decides what to do when `bundleID` becomes frontmost.
    ///
    /// A protected, not-yet-unlocked app is covered. A regular (Dock-owning) app
    /// switching in means the user left the locked app, so the overlay comes
    /// down. Menu-bar agents and other helpers do not count, which keeps system
    /// prompts from unmasking a locked app.
    func decisionOnActivate(bundleID: String, isRegularApp: Bool) -> Decision {
        if bundleID == selfBundleID { return .ignore }
        if protectedBundleIDs.contains(bundleID) {
            return unlockedBundleIDs.contains(bundleID) ? .hideLock : .showLock
        }
        return isRegularApp ? .hideLock : .ignore
    }

    /// Whether losing focus should re-arm the lock for this app.
    func shouldReArm(bundleID: String, lockOnAppSwitch: Bool) -> Bool {
        lockOnAppSwitch && protectedBundleIDs.contains(bundleID)
    }
}
