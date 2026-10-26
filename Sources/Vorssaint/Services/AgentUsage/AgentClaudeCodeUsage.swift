// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Claude Code's own `/usage`, asked of its command-line tool: the plan's
/// limits as the account reports them, with each model's own week, such as
/// Fable's, and the exact time each renews. Claude Code asks with its own
/// sign-in, which Vorssaint never reads; nothing is kept but the lines it
/// prints, and no session is saved.
enum AgentClaudeCodeUsage {
    static let timeout: TimeInterval = 20
    /// A reading this recent stands over the Claude app's, which lacks a
    /// model's own week and the exact renewals.
    static let precedence: TimeInterval = 15 * 60
    static let arguments = ["-p", "/usage", "--no-session-persistence", "--setting-sources", ""]

    /// Where the official installer, the older npm-local install, Homebrew
    /// and npm put it, then along a shell's PATH when one was asked for.
    static func candidates(home: URL, searchPath: String? = nil) -> [URL] {
        let folders = [home.appending(path: ".local/bin").path, home.appending(path: ".claude/local").path,
                       "/opt/homebrew/bin", "/usr/local/bin"]
            + (searchPath ?? "").split(separator: ":").map(String.init).filter { $0.hasPrefix("/") }
        return folders.map { URL(fileURLWithPath: $0, isDirectory: true).appending(path: "claude") }
    }

    static func executable(home: URL, searchPath: String? = nil) -> URL? {
        candidates(home: home, searchPath: searchPath).first { url in
            var directory: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &directory) && !directory.boolValue
                && FileManager.default.isExecutableFile(atPath: url.path)
        }
    }

    static func read(_ executable: URL, searchPath: String?, now: Date = Date()) -> AgentLimits? {
        let environment = AgentCodexServer.environment(for: executable, searchPath: searchPath)
        let result = BoundedProcessRunner.runInNewSession(executable.path, arguments, timeout: timeout,
                                                          maxOutputBytes: 1 << 20, environment: environment)
        guard !result.timedOut, result.status == 0 else { return nil }
        return limits(from: String(decoding: result.output, as: UTF8.self), now: now)
    }

    // MARK: Lines

    /// "Current session: 90% used · resets Oct 22 at 1:59am (America/Toronto)"
    /// and "Current week (Fable): 14% used · …". Nil when no line is a limit,
    /// as for an API key, which has none.
    static func limits(from text: String, now: Date) -> AgentLimits? {
        let pattern = #"^Current (session|week \(([^)]+)\)): (\d+(?:\.\d+)?)% used(?: · resets (.+?)(?: \(([^()]+)\))?)?$"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return nil }
        var windows: [AgentLimitWindow] = []
        for line in text.split(whereSeparator: \.isNewline).map({ $0.trimmingCharacters(in: .whitespaces) }) {
            let range = NSRange(line.startIndex..., in: line)
            guard let match = expression.firstMatch(in: line, range: range) else { continue }
            func group(_ index: Int) -> String? { Range(match.range(at: index), in: line).map { String(line[$0]) } }
            guard let used = group(3).flatMap(Double.init), used.isFinite else { continue }
            let session = group(1) == "session"
            let scope = session ? nil : group(2).flatMap(scopeName)
            let zone = group(5).flatMap(TimeZone.init(identifier:)) ?? .current
            let resets = group(4).flatMap { resetDate($0, timeZone: zone, now: now) }
            let id = "claude.code." + (session ? "session" : "week" + (scope.map { "." + $0.lowercased() } ?? ""))
            guard !windows.contains(where: { $0.id == id }) else { continue }
            windows.append(AgentLimitWindow(id: id, kind: session ? .session : .weekly, minutes: session ? 300 : 10_080,
                                            scope: scope, usedPercent: min(100, max(0, used)), resetsAt: resets))
        }
        guard !windows.isEmpty else { return nil }
        return AgentLimits(provider: .claude, windows: windows, observedAt: now, source: .account)
    }

    /// "all models" covers the plan; "Sonnet only" is Sonnet's own week.
    private static func scopeName(_ label: String) -> String? {
        let name = label.trimmingCharacters(in: .whitespaces)
        if name.lowercased() == "all models" { return nil }
        return name.hasSuffix(" only") ? String(name.dropLast(5)) : name
    }

    /// "Oct 22 at 1:59am", "Oct 22, 2027 at 1:59am" or "1:59am", in the
    /// zone the line names. A date without a year is the next one to come.
    static func resetDate(_ text: String, timeZone: TimeZone, now: Date) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.amSymbol = "am"
        formatter.pmSymbol = "pm"
        formatter.defaultDate = now
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let value = text.trimmingCharacters(in: .whitespaces)
        for format in ["MMM d, yyyy 'at' h:mma", "MMM d, yyyy 'at' ha", "MMM d, yyyy"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: value) { return date }
        }
        for format in ["MMM d 'at' h:mma", "MMM d 'at' ha", "MMM d"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: value) {
                return date < now.addingTimeInterval(-86_400) ? calendar.date(byAdding: .year, value: 1, to: date) : date
            }
        }
        for format in ["h:mma", "ha"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: value) {
                return date < now ? calendar.date(byAdding: .day, value: 1, to: date) : date
            }
        }
        return nil
    }
}
