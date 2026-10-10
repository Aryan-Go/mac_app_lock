# App Lock

A focus-driven app locker for macOS. Pick the apps you want to keep private, and
the moment any of them comes to the front it's covered by a blurred lock screen
that asks for your passcode or Touch ID. Switch away and it re-arms, so every time
you come back you have to unlock it again.

## What it does

- **Locks when you switch to an app, not just when it launches.** Apps you're
  already using stay protected — switch to Mail and it locks, switch away and it's
  ready to lock again next time.
- **Covers the app's window, not your whole screen.** The blur sits over just the
  protected app's windows, so the rest of your desktop stays usable. A setting
  switches it to a full-screen lock if you prefer.
- **Unlock with a passcode or Touch ID.** Type your 4- or 6-digit passcode right
  onto the lock screen, or tap the Touch ID button.
- **Pick apps anytime.** Search your installed apps, flip a switch, or drag in a
  `.app`. Nothing is fixed at setup — change your list whenever you like.
- **Handles multiple windows and displays.** Every window of a protected app gets
  covered, and the lock follows the window as it moves or resizes.
- **Re-lock triggers you control.** Choose to re-lock when you switch away, when
  the Mac sleeps, when the screen locks, or after a period of inactivity.
- **Stays out of your way.** It lives in the menu bar with an optional Dock icon,
  ready whenever you need it.

## Requirements

- macOS 13 or newer.
- No Accessibility, Screen Recording, or Full Disk Access permission needed.

## Install

```bash
make app          # builds AppLock.app into ./dist
open dist/AppLock.app
```

To have it start automatically and keep running:

```bash
make install      # builds, copies to /Applications, and adds it to your login items
make uninstall    # removes the app, login item, and config
```

## Using it

| Action | Result |
| --- | --- |
| First launch | The manager opens — set a passcode, then switch on the apps you want to protect |
| Apps tab | Search, toggle, drag a `.app` in, or use "Add App…" at any time |
| Settings tab | Change your passcode, when to lock, window vs. full-screen coverage, Touch ID, appearance, and more |
| Menu bar lock icon | Manage Apps, Lock Protected Apps Now, Dismiss Lock Screen, or Quit |
| On a locked app | Type your passcode (⌫ to correct) or click the Touch ID button |
| ⌃⌥⇧⌘U | Dismiss any lock screen immediately |

Apps you've switched on are only actually locked once you've set a passcode. Until
then, the manager shows a banner prompting you to set one.

## Safety and recovery

- **Forgetting your passcode.** Press ⌃⌥⇧⌘U to dismiss the lock screen, then turn
  protection off in the manager (or quit App Lock from the menu bar). The passcode
  can't be recovered or read back — it's stored only as a secure hash.
- **Emergency dismiss.** ⌃⌥⇧⌘U clears any lock screen from anywhere, no matter
  what's on screen.
- **System apps are protected from you.** Core parts of macOS (Finder, Dock,
  login window, System Settings, Spotlight, and so on) can never be locked, so you
  can't lock yourself out.
- **Risky apps are flagged.** Apps that could strand you if locked (Terminal,
  Activity Monitor, Xcode) are marked in the list — but you're still free to
  protect them if you want.
