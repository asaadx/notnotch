// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Asks Claude Code for its limits while the AI page shows Claude, at most
/// every few minutes, and hands what it says to the usage service.
final class AgentClaudeCodeUsageService {
    static let shared = AgentClaudeCodeUsageService()

    static let freshness: TimeInterval = 5 * 60

    private let queue = DispatchQueue(label: "com.vorssaint.claude-code-usage", qos: .utility)
    private var attempted = Date.distantPast
    private var checking = false

    private init() {}

    func refreshIfStale(now: Date = Date()) {
        guard !checking, now.timeIntervalSince(attempted) >= Self.freshness else { return }
        checking = true
        attempted = now
        queue.async { [weak self] in
            let home = FileManager.default.homeDirectoryForCurrentUser
            let limits = AgentClaudeCodeUsage.executable(home: home).flatMap {
                AgentClaudeCodeUsage.read($0, searchPath: nil)
            }
            DispatchQueue.main.async {
                self?.checking = false
                if let limits { AgentUsageService.shared.noteLimits(limits) }
            }
        }
    }
}
