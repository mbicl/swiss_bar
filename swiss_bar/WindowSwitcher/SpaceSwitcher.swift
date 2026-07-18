//
//  SpaceSwitcher.swift
//  swiss_bar
//

import AppKit
import CoreGraphics
import os

// MARK: - CoreGraphics private (SkyLight) Space APIs
//
// On current macOS the Accessibility API only exposes windows on the currently-displayed Space of
// each display, and SkyLight's focus-by-ID doesn't switch Spaces on its own. To activate a window
// parked on another Space we must first move that display to the window's Space. These CGS
// functions are the mechanism yabai and alt-tab-macos use. Symbols are resolved individually via
// dlsym (verified present on this OS: CGSCopyBestManagedDisplayForSpace is NOT, so we use
// CGSCopyManagedDisplayForSpace instead) so a missing one disables only what depends on it.

private typealias CGSConnectionID = Int32
private typealias MainConnectionIDFunc = @convention(c) () -> CGSConnectionID
private typealias CopySpacesForWindowsFunc = @convention(c) (CGSConnectionID, Int32, CFArray) -> Unmanaged<CFArray>?
private typealias CopyDisplayForSpaceFunc = @convention(c) (CGSConnectionID, UInt64) -> Unmanaged<CFString>?
private typealias SetCurrentSpaceFunc = @convention(c) (CGSConnectionID, CFString, UInt64) -> CGError
private typealias SpaceGetTypeFunc = @convention(c) (CGSConnectionID, UInt64) -> Int32
private typealias GetActiveSpaceFunc = @convention(c) (CGSConnectionID) -> UInt64
private typealias DisplayCurrentSpaceFunc = @convention(c) (CGSConnectionID, CFString) -> UInt64

/// Includes all Space types (user, fullscreen, system) - the mask value yabai uses.
private let kCGSAllSpacesMask: Int32 = 0x7
/// `CGSSpaceGetType` return value for a fullscreen Space (0 = normal user Space).
private let kCGSSpaceTypeFullscreen: Int32 = 4

private let skyLight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)

private func cgsSymbol<T>(_ name: String, as type: T.Type) -> T? {
    guard let skyLight, let sym = dlsym(skyLight, name) else { return nil }
    return unsafeBitCast(sym, to: T.self)
}

private let cgsMainConnectionID = cgsSymbol("CGSMainConnectionID", as: MainConnectionIDFunc.self)
private let cgsCopySpacesForWindows = cgsSymbol("CGSCopySpacesForWindows", as: CopySpacesForWindowsFunc.self)
private let cgsCopyDisplayForSpace = cgsSymbol("CGSCopyManagedDisplayForSpace", as: CopyDisplayForSpaceFunc.self)
private let cgsSetCurrentSpace = cgsSymbol("CGSManagedDisplaySetCurrentSpace", as: SetCurrentSpaceFunc.self)
private let cgsSpaceGetType = cgsSymbol("CGSSpaceGetType", as: SpaceGetTypeFunc.self)
private let cgsGetActiveSpace = cgsSymbol("CGSGetActiveSpace", as: GetActiveSpaceFunc.self)
private let cgsManagedDisplayGetCurrentSpace = cgsSymbol("CGSManagedDisplayGetCurrentSpace", as: DisplayCurrentSpaceFunc.self)

enum SpaceSwitcher {

    private static let logger = Logger(subsystem: "com.MBI.swiss-bar", category: "SpaceSwitcher")

    /// The Space ID that `windowID` currently lives on, or nil if it can't be resolved.
    static func spaceID(of windowID: CGWindowID) -> UInt64? {
        guard let mainConnectionID = cgsMainConnectionID, let copySpaces = cgsCopySpacesForWindows else { return nil }
        let cid = mainConnectionID()
        guard let raw = copySpaces(cid, kCGSAllSpacesMask, [windowID] as CFArray)?.takeRetainedValue(),
              let spaces = raw as? [Int], let first = spaces.first else { return nil }
        return UInt64(first)
    }

    private static func isFullscreen(_ spaceID: UInt64) -> Bool {
        guard let mainConnectionID = cgsMainConnectionID, let getType = cgsSpaceGetType else { return false }
        return getType(mainConnectionID(), spaceID) == kCGSSpaceTypeFullscreen
    }

    /// The Space currently shown on the display that owns `spaceID`'s Space grouping, or nil if
    /// undeterminable. More accurate than the global `CGSGetActiveSpace` on multi-display setups,
    /// where each display tracks its own active Space independently - a fullscreen app on one
    /// display must not affect classification of a switch happening on another display. Falls
    /// back to `cgsGetActiveSpace` (single-display behavior) if the per-display symbol or the
    /// owning display can't be resolved.
    private static func currentSpace(onDisplayOwning spaceID: UInt64, cid: CGSConnectionID) -> UInt64? {
        guard let copyDisplay = cgsCopyDisplayForSpace,
              let displayUUID = copyDisplay(cid, spaceID)?.takeRetainedValue(),
              let getCurrentSpace = cgsManagedDisplayGetCurrentSpace else {
            return cgsGetActiveSpace?(cid)
        }
        return getCurrentSpace(cid, displayUUID)
    }

    /// True if activating `windowID` crosses into or out of a fullscreen Space. Such transitions
    /// must be driven by macOS's native app activation (no CGS switch, no AX raise) - forcing the
    /// display or raising a cross-Space window both composite it onto the wrong Space.
    static func involvesFullscreen(windowID: CGWindowID) -> Bool {
        guard let cid = cgsMainConnectionID?(), let target = spaceID(of: windowID) else { return false }
        if isFullscreen(target) { return true }
        if let current = currentSpace(onDisplayOwning: target, cid: cid), isFullscreen(current) { return true }
        return false
    }

    /// True if `pid`'s app already has a window on the currently active Space. When true, plain
    /// `NSRunningApplication.activate()` is a no-op for switching to a *different* Space-bound
    /// window of that app (macOS just keeps showing the current-Space window instead of jumping
    /// Spaces), so the caller needs a stronger mechanism (SkyLight focus-by-ID) instead.
    static func hasWindowOnActiveSpace(pid: pid_t) -> Bool {
        guard let mainConnectionID = cgsMainConnectionID, let getActiveSpace = cgsGetActiveSpace else { return false }
        let cid = mainConnectionID()
        let activeSpace = getActiveSpace(cid)
        guard let axWindows = WindowEnumerator.axWindows(for: pid) else { return false }
        for axWindow in axWindows {
            guard let wid = WindowEnumerator.windowID(of: axWindow) else { continue }
            if spaceID(of: wid) == activeSpace { return true }
        }
        return false
    }

    /// Navigates to the Space containing `windowID` when a direct CGS switch is the right tool -
    /// i.e. a normal→normal Space change that plain app activation won't perform. Returns false
    /// (does nothing) when the target or the current Space is fullscreen: for those, forcing the
    /// display with `CGSManagedDisplaySetCurrentSpace` composites the window onto the wrong Space
    /// and corrupts fullscreen UI, so the caller must instead rely on macOS's native
    /// app-activation, which animates fullscreen transitions correctly.
    @discardableResult
    static func switchToSpace(of windowID: CGWindowID) -> Bool {
        guard let mainConnectionID = cgsMainConnectionID,
              let copyDisplay = cgsCopyDisplayForSpace,
              let setSpace = cgsSetCurrentSpace else {
            logger.notice("CGS Space symbols unavailable (main=\(cgsMainConnectionID != nil) display=\(cgsCopyDisplayForSpace != nil) set=\(cgsSetCurrentSpace != nil))")
            return false
        }
        guard let spaceID = spaceID(of: windowID) else {
            logger.notice("no Space found for window \(windowID)")
            return false
        }

        let cid = mainConnectionID()
        let currentSpaceID = currentSpace(onDisplayOwning: spaceID, cid: cid)
        let targetFullscreen = isFullscreen(spaceID)
        let currentFullscreen = currentSpaceID.map(isFullscreen) ?? false
        if targetFullscreen || currentFullscreen {
            logger.notice("skip CGS switch (fullscreen involved) target=\(spaceID) fs=\(targetFullscreen) current=\(currentSpaceID ?? 0) fs=\(currentFullscreen) - using native activation")
            return false
        }

        guard let displayUUID = copyDisplay(cid, spaceID)?.takeRetainedValue() else {
            logger.notice("no display found for Space \(spaceID)")
            return false
        }

        let result = setSpace(cid, displayUUID, spaceID)
        logger.notice("switchToSpace window=\(windowID) space=\(spaceID) result=\(result.rawValue)")
        return result == .success
    }
}
