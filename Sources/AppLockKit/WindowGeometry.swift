import AppKit

/// Finds where a running app's windows actually are, so the lock screen can be
/// sized to the app rather than the display.
///
/// This uses `CGWindowListCopyWindowInfo`, which reports window bounds and owner
/// pids without requiring Screen Recording or Accessibility permission. (Only
/// window *titles* are gated, and we don't need those.)
enum WindowGeometry {

    /// Matched to the standard macOS window corner so the overlay's rounded
    /// corners sit flush with the window it covers.
    static let windowCornerRadius: CGFloat = 12

    /// Anything smaller is a shadow, tooltip or HUD rather than a window worth
    /// covering.
    private static let minimumCapturedSide: CGFloat = 32
    private static let minimumClusterWidth: CGFloat = 200
    private static let minimumClusterHeight: CGFloat = 120

    /// Lock-screen-sized regions for `pid`, in Cocoa screen coordinates. Empty
    /// when the app has no visible window.
    ///
    /// Many apps (Brave, VS Code, Ghostty…) report their chrome as several
    /// adjacent layer-0 windows, so nearby frames are merged before being
    /// returned — otherwise a 40pt toolbar strip would get a lock screen of its
    /// own.
    static func onScreenWindowFrames(forPID pid: pid_t) -> [CGRect] {
        guard let raw = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return [] }

        var frames: [CGRect] = []
        for info in raw {
            guard let owner = info[kCGWindowOwnerPID as String] as? Int, owner == Int(pid) else { continue }
            // Layer 0 is normal app windows; panels, menus and shadows sit above.
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
            guard let bounds = info[kCGWindowBounds as String] as? [String: Any],
                  let cgRect = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { continue }
            guard cgRect.width >= minimumCapturedSide, cgRect.height >= minimumCapturedSide else { continue }
            frames.append(cocoaRect(fromCG: cgRect, primaryHeight: primaryScreenHeight))
        }

        return coverableRegions(from: frames)
    }

    /// Picks the regions worth covering. Substantial ones win so stray HUDs and
    /// tooltips don't each get a lock screen of their own — but if an app has
    /// nothing substantial, its small windows are covered rather than falling
    /// back to blanketing the whole display.
    static func coverableRegions(from frames: [CGRect]) -> [CGRect] {
        let clusters = cluster(frames)
        let substantial = clusters.filter {
            $0.width >= minimumClusterWidth && $0.height >= minimumClusterHeight
        }
        return substantial.isEmpty ? clusters : substantial
    }

    /// Merges rectangles that touch or overlap (within `gap`) into their union,
    /// transitively. Two far-apart windows stay separate; a stack of stacked
    /// toolbars collapses into the one window they belong to.
    static func cluster(_ frames: [CGRect], gap: CGFloat = 8) -> [CGRect] {
        var pending = frames
        var result: [CGRect] = []

        while let seed = pending.first {
            pending.removeFirst()
            var region = seed
            var merged = true

            while merged {
                merged = false
                var leftovers: [CGRect] = []
                for rect in pending {
                    if region.insetBy(dx: -gap, dy: -gap).intersects(rect) {
                        region = region.union(rect)
                        merged = true
                    } else {
                        leftovers.append(rect)
                    }
                }
                pending = leftovers
            }

            result.append(region)
        }

        return result
    }

    /// CG window bounds use a top-left origin anchored to the primary display;
    /// Cocoa windows use a bottom-left origin. Split out so it can be tested
    /// without a live display.
    static func cocoaRect(fromCG rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(
            x: rect.minX,
            y: primaryHeight - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    /// The "zero screen" is the one whose Cocoa frame origin is (0, 0), and it is
    /// the reference for the flip.
    private static var primaryScreenHeight: CGFloat {
        NSScreen.screens.first?.frame.height ?? NSScreen.main?.frame.height ?? 0
    }
}
