# App Lock

A focus-driven app locker for macOS. Pick the apps you care about, and the moment
any of them comes to the front it is covered by a blurred lock screen that asks
for a passcode or Touch ID. The instant you switch away it re-arms, so every
return needs authenticating again.

Built from scratch with AppKit + SwiftUI. No Xcode project — just Swift Package
Manager, like `macnotch`.

---

## What it does

- **Locks on focus, not just on launch.** The interesting case is an app that is
  *already running*: switch to Mail and it locks, switch away and it re-arms.
  Launch-only gates (what sandboxed App Store lockers can do) miss this entirely.
- **Covers the app's window, not your screen.** The lock screen is sized to the
  app's own windows and blurs exactly what is underneath, so the rest of the
  desktop stays usable. A setting switches it back to a full-screen lock.
- **Blurs, doesn't just dim.** A panel parked above everything hosts an
  `NSVisualEffectView` with `.behindWindow` blending, so the compositor's own
  blur is applied to the app underneath.
- **Type the passcode straight in.** No on-screen keypad — you're on a laptop.
  Dots fill as you type, ⌫ deletes, and it submits when you reach the right
  length. Wrong code → shake plus a trackpad haptic.
- **Touch ID / Face ID equivalent.** `LocalAuthentication` drives the sensor, with
  an "Unlock with Touch ID" button on the lock screen. Calling it automatically
  the moment an app locks is a separate, **off-by-default** setting — the system
  biometric sheet is a modal, so popping it on every app switch fights with just
  typing the passcode.
- **Numeric passcode.** 4 or 6 digits, stored as a salted SHA-256 hash in the
  Keychain. The plaintext is never written anywhere.
- **Pick apps any time.** A single scrollable list of everything installed, one
  switch per app, a search box and an All/Protected filter — plus drag-and-drop
  of a `.app`. Nothing is fixed at first launch.
- **Multi-window and multi-display.** Each of the protected app's windows gets a
  lock panel, and they follow the window if the app moves or resizes it.
- **Re-lock triggers you can toggle:** switching away, sleep, screen lock, idle.
- **Safety:** a system blacklist that can never be locked, and an emergency
  hotkey (⌃⌥⇧⌘U) that dismisses any lock screen instantly.
- **Runs in front.** A normal windowed app with a Dock icon plus a menu bar item,
  so you can open the manager whenever you want. Closing the window keeps it
  running.

---

## How it works

### 1. Watching focus

`AppMonitor` subscribes to `NSWorkspace`'s activate / deactivate / terminate
notifications. `AppLockController` turns those into lock decisions through
`LockPolicy`, a pure function that is unit-tested:

| Situation | Result |
| --- | --- |
| Protected app becomes frontmost, not authenticated | show the lock screen |
| Protected app becomes frontmost, already authenticated | take the lock screen down |
| A regular (Dock-owning) app becomes frontmost | take the lock screen down |
| A menu-bar agent / system helper becomes frontmost | ignore |
| AppLock itself becomes frontmost | ignore |
| Protected app loses focus, `lockOnAppSwitch` on | re-arm it |

Treating only *regular* activations as "the user switched apps" is what keeps
system prompts (security agents, biometric UI) from unmasking a locked app.

### 2. Finding the app's window

`WindowGeometry` uses `CGWindowListCopyWindowInfo` to list the app's on-screen,
layer-0 windows and turn their bounds into Cocoa coordinates (CG bounds are
top-left origin anchored to the primary display; Cocoa is bottom-left — that flip
is unit-tested).

Nearby frames are then **clustered into one region**. That step matters more than
it sounds: Brave, VS Code and Ghostty report their chrome as several adjacent
layer-0 windows (a 40pt strip here, a 151pt strip there), and covering each
individually would put a broken lock screen inside a toolbar. Clustering is
unit-tested against that exact shape. Regions too small to be a real window are
skipped, unless nothing else is available.

This matters because it needs **no Screen Recording and no Accessibility
permission**. (Only window *titles* are gated behind Screen Recording, and we
don't need those.) If no window can be found — or if you turn the setting off —
it falls back to covering every display.

### 3. Blur and geometry

One `LockOverlayPanel` is created per window target:

- `.borderless`, `level = .screenSaver` → above everything.
- `collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary,
  .ignoresCycle]` → follows you across Spaces and stays over full-screen apps.
- `isOpaque = false`, `backgroundColor = .clear`, custom `canBecomeKey`.
- Corner radius matched to the window so the overlay sits flush with it.

The panel's backdrop is an `NSVisualEffectView` with
`blendingMode = .behindWindow`, `material = .fullScreenUI`, dark appearance. A
behind-window effect view samples the window server's backdrop — which is the app
we are covering. A scrim and a soft radial gradient sit on top, then the SwiftUI
lock screen. Panels are pooled and reused, so re-locking has no first-paint
flash, and a 0.25s poll repositions them if the app moves its own window.

### 4. Keeping the app out

Because the overlay is a real key window of an active app, keyboard and mouse
input goes to the lock screen rather than the app beneath it. On top of that,
`OverlayManager` installs a local key monitor while locked: digits and delete
drive the passcode field, Cmd+Tab is allowed through (so you can leave), and
everything else is swallowed — including Cmd+Q, so the lock screen can't be
dismissed with the keyboard.

One consequence of activating the app: macOS raises *our* windows too. The
manager window is therefore hidden for the duration of a lock and restored
afterwards, so the blur always samples the protected app rather than our own UI.

### 5. Authenticating

- **Passcode** — `PasscodeStore` keeps `hex(salt)$hex(SHA256(salt + pin))` in the
  login Keychain (generic password, `kSecAttrAccessibleWhenUnlocked`).
  Verification is constant-time.
- **Biometrics** — `LocalAuthentication` with
  `.deviceOwnerAuthenticationWithBiometrics`. Cancel falls through to typing; a
  failure shows an inline message.

  Note the division of labour: the Touch ID sheet itself is drawn by macOS, so it
  can't be restyled or made to read silently. What the app controls is *when*
  `evaluatePolicy` is called. By default that is only when you tap the button;
  the "Ask for Touch ID automatically" setting opts into prompting on every lock.

### 6. Testable seams

`Passcode` is a thin facade over `PasscodeStore`, and `Store` takes an optional
directory. Both exist so the test suite can exercise real Keychain and on-disk
round-trips against scratch locations instead of your actual data.

### 7. System hooks

- **Idle** — `IdleMonitor` takes the minimum of
  `CGEventSource.secondsSinceLastEventType` across several event types, i.e. the
  time since the most recent input of any kind. No permission needed.
- **Sleep / wake** — `NSWorkspace.willSleepNotification` / `didWakeNotification`.
- **Screen lock** — `DistributedNotificationCenter`'s `com.apple.screenIsLocked`.
- **Emergency hotkey** — Carbon `RegisterEventHotKey`, which works without the
  Accessibility permission an event tap would require.

---

## Requirements

- macOS 13 or newer (developed on macOS 26).
- Xcode command line tools (`xcode-select --install`).
- No Accessibility, Screen Recording or Full Disk Access permission is required.
  Touch ID uses the system prompt.

---

## Build and run

```bash
# run from source
make run

# tests
swift test

# build a real .app bundle into ./dist
make app
open dist/AppLock.app
```

---

## Install so it stays running

```bash
make install      # builds, copies to /Applications, registers a LaunchAgent
make uninstall    # removes app, login item and config
```

AppLock also exposes the `applock://manage` URL scheme, so another app (for
example a notch overlay) can open the manager with `open applock://manage`.

---

## Using it

| Action | Result |
| --- | --- |
| First launch | Manager opens; set a passcode, then switch on the apps you want |
| Apps tab | Search, toggle, drag a `.app` in, or "Add App…" — at any time |
| Settings tab | Passcode, when to lock, window vs. full-screen coverage, Touch ID, darkness, Dock icon, login item, hotkey |
| Menu bar lock icon | Manage Apps, Lock Protected Apps Now, Dismiss Lock Screen, Quit |
| On a locked app | Type the passcode (⌫ to correct), or click the Touch ID button |
| ⌃⌥⇧⌘U | Dismiss any lock screen immediately |

Covered apps are only locked once a passcode exists — until then the manager
shows a banner prompting you to set one.

---

## Safety

- **System blacklist.** Finder, Dock, SystemUIServer, WindowServer, loginwindow,
  Control Center, Notification Center, Spotlight, System Settings, SecurityAgent
  and friends can never be protected (`SystemApps.neverLock`).
- **Emergency hotkey.** ⌃⌥⇧⌘U dismisses every overlay from anywhere.
- **Recovery.** If you forget the passcode, dismiss with the hotkey and turn
  protection off in the manager, or quit AppLock from the menu bar. There is no
  way to read the passcode back out of the Keychain.
- **Warning badges.** Apps that can strand you if locked (Terminal, Activity
  Monitor, Xcode) are flagged in the list but still allowed.

---

## Project layout

```
Package.swift                       SwiftPM: AppLockKit library + AppLock executable + tests
Makefile                            build / run / app / install / uninstall
Resources/Info.plist                Bundle metadata (LSMinimumSystemVersion, URL scheme, …)
scripts/build-app.sh                Builds dist/AppLock.app
scripts/install.sh                  /Applications + LaunchAgent
scripts/uninstall.sh                Removes everything
Sources/AppLock/main.swift          Three-line executable entry point
Sources/AppLockKit/
  AppLockKit.swift                  run() + single-instance guard
  AppDelegate.swift                 Wiring, menu bar item, Dock policy
  Models.swift                      ProtectedApp, AppInfo, AppSettings
  Store.swift                       Settings + protected list, JSON in Application Support
  InstalledApps.swift               Scans /Applications, /System/Applications, ~/Applications
  Passcode.swift                    PasscodeStore — Keychain, salted SHA-256
  AuthManager.swift                 LocalAuthentication wrapper
  AppMonitor.swift                  NSWorkspace focus notifications
  LockPolicy.swift                  Pure "when do we lock" decision (tested)
  WindowGeometry.swift              Finds the app's windows via CGWindowList (tested)
  AppLockController.swift           The state machine
  SystemSupport.swift               Idle, sleep/screen hooks, launch-at-login, hotkey, blacklist
  LockOverlayPanel.swift            Panel per window, blur, keyboard capture
  LockOverlayView.swift             The lock screen UI (dots, hint, biometric button)
  DesignSystem.swift                Haptics, shake effect, cards
  ManagerWindowController.swift     The manager window (hidden while locked)
  ManagerView.swift                 Apps / Settings / About tabs, passcode sheet
Tests/AppLockKitTests/              37 tests: lock policy, geometry, passcode, store, scanning
```

---

## Not included (yet)

- **Frozen snapshot blur.** The blur is live; a captured still would look more
  like iOS, but needs Screen Recording permission and gains little.
- **Auto-close protected apps** to stop notification snooping on a shared Mac.
- **Apple Watch proximity unlock.**
- **MacNotch integration.** The `applock://manage` scheme is the hook; a notch
  tab could open the manager with `NSWorkspace.open`, without either project
  importing the other.
