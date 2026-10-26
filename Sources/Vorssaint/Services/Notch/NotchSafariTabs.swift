// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreServices

/// Safari, asked over Apple Events from this process so the consent is this
/// app's own. Nothing here starts Safari: every call checks that it is
/// already running, since `tell application` would otherwise launch it.
/// Each call blocks on Safari's reply, so callers keep them off the main
/// thread, on one serial queue.
enum NotchSafariTabs {
    static let bundleIdentifier = "com.apple.Safari"

    enum Access: Equatable {
        case notRunning, granted, consent, denied, unavailable
    }

    enum Reply: Equatable {
        case ok(String)
        /// Automation of Safari was declined.
        case denied
        /// Safari refuses `do JavaScript` until its Developer settings allow it.
        case javaScriptOff
        case failed
    }

    static var isRunning: Bool {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).contains { !$0.isTerminated }
    }

    /// Never asks; a Safari that is not running cannot be asked about.
    static func access() -> Access {
        guard isRunning else { return .notRunning }
        var target = AEAddressDesc()
        let created = bundleIdentifier.withCString { pointer in
            AECreateDesc(typeApplicationBundleID, pointer, bundleIdentifier.utf8.count, &target)
        }
        guard created == noErr else { return .unavailable }
        defer { AEDisposeDesc(&target) }
        switch AEDeterminePermissionToAutomateTarget(&target, typeWildCard, typeWildCard, false) {
        case noErr: return .granted
        case OSStatus(errAEEventWouldRequireUserConsent): return .consent
        case OSStatus(errAEEventNotPermitted): return .denied
        default: return .unavailable
        }
    }

    /// Shows the system's question when it has not been answered yet.
    @discardableResult
    static func requestAccess() -> Bool {
        guard isRunning else { return false }
        return AppleScriptRunner.consentToAutomate(bundleID: bundleIdentifier)
    }

    static func tabs() -> [NotchSafariTab]? {
        guard case .ok(let output) = run(NotchVideoNotesSupport.tabsScript) else { return nil }
        return NotchVideoNotesSupport.parseTabs(output)
    }

    static func state(of tab: NotchSafariTab) -> (reply: Reply, state: NotchVideoState?) {
        let reply = run(NotchVideoNotesSupport.javaScriptScript(NotchVideoNotesSupport.stateJavaScript, in: tab))
        guard case .ok(let output) = reply else { return (reply, nil) }
        return (reply, NotchVideoNotesSupport.parseState(output, at: Date()))
    }

    static func javaScript(_ source: String, in tab: NotchSafariTab) -> Reply {
        run(NotchVideoNotesSupport.javaScriptScript(source, in: tab))
    }

    @discardableResult
    static func open(_ url: String, in tab: NotchSafariTab) -> Bool {
        if case .ok = run(NotchVideoNotesSupport.openScript(url, in: tab)) { return true }
        return false
    }

    static func show(_ tab: NotchSafariTab) {
        _ = run(NotchVideoNotesSupport.showScript(tab))
    }

    private static func run(_ source: String) -> Reply {
        guard isRunning, access() == .granted else { return .denied }
        let result = AppleScriptRunner.runDetailed(source)
        if result.ok { return .ok(result.output) }
        // -1743 declined, -1744 would need consent.
        if result.errorNumber == -1743 || result.errorNumber == -1744 { return .denied }
        // Safari answers `do JavaScript` with its own error when the
        // Developer setting is off.
        if result.message.localizedCaseInsensitiveContains("JavaScript") { return .javaScriptOff }
        return .failed
    }
}
