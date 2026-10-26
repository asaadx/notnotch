// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The AI page: each agent's plan allowances, a row apiece, read like the
/// usage page of the agent's own account.
struct NotchAgentsView: View {
    let size: CGSize
    @ObservedObject private var usage = AgentUsageService.shared
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.notchAgentsLimitDisplay) private var display = NotchAgentLimitDisplay.remaining.rawValue
    @AppStorage(DefaultsKey.notchAgentsClaude) private var claude = true
    @AppStorage(DefaultsKey.notchAgentsCodex) private var codex = true
    @AppStorage(DefaultsKey.notchAgentsOpenCode) private var opencode = true
    @AppStorage(DefaultsKey.notchAgentsCopilot) private var copilot = true

    private var text: NotchAgentStrings { FeatureStrings.notchAgents(l10n.language) }

    /// Only agents that left something on this Mac and report allowances.
    private var providers: [AgentProvider] {
        NotchAgentSupport.pageProviders(
            [claude ? AgentProvider.claude : nil, codex ? .codex : nil, opencode ? .opencode : nil, copilot ? .copilot : nil]
                .compactMap { $0 }.filter(usage.snapshot.seen.contains))
    }

    var body: some View {
        Group {
            if !usage.snapshot.loaded {
                VStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(text.loading).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if providers.isEmpty {
                NotchEmptyView(symbol: "sparkles", message: text.empty)
            } else {
                let providers = providers
                TimelineView(.periodic(from: .now, by: 15)) { context in
                    if NotchAgentSupport.contentHeight(usage.snapshot, providers: providers, now: context.date)
                        > size.height + 0.5 {
                        ScrollView { list(providers, now: context.date) }
                            .scrollIndicators(.automatic)
                    } else {
                        list(providers, now: context.date)
                    }
                }
            }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .environment(\.locale, l10n.language.formattingLocale())
        .onAppear { usage.pageDidAppear() }
    }

    private func list(_ providers: [AgentProvider], now: Date) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(providers.enumerated()), id: \.element) { index, provider in
                if index > 0 {
                    Rectangle().fill(.white.opacity(0.1)).frame(height: 1)
                        .frame(height: NotchAgentSupport.sectionGap)
                }
                NotchAgentUsageSection(provider: provider, snapshot: usage.snapshot, now: now,
                                       display: NotchAgentLimitDisplay(rawValue: display) ?? .remaining, text: text)
            }
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, alignment: .top)
    }
}

// MARK: Section

/// One agent: its name and plan, then a row for every allowance.
private struct NotchAgentUsageSection: View {
    let provider: AgentProvider
    let snapshot: AgentUsageSnapshot
    let now: Date
    let display: NotchAgentLimitDisplay
    let text: NotchAgentStrings
    @Environment(\.locale) private var locale

    /// A reading the Claude app saved a while ago: still the latest known,
    /// shown quieter until the app checks again.
    private var stale: Bool {
        guard let limits = snapshot.limits[provider], limits.source == .claudeApp else { return false }
        return now.timeIntervalSince(limits.observedAt) >= AgentClaudeAppUsage.freshness
    }

    var body: some View {
        let windows = NotchAgentSupport.windows(snapshot, provider: provider, now: now)
        VStack(alignment: .leading, spacing: NotchAgentSupport.rowSpacing) {
            header
            if windows.isEmpty {
                placeholder
            } else {
                ForEach(windows) { row($0) }
                    .opacity(stale ? 0.6 : 1)
            }
            if provider == .codex { NotchAgentResetsRow(now: now, text: text) }
        }
        .onAppear(perform: askClaudeCode)
        .onChange(of: now) { _, _ in askClaudeCode() }
    }

    /// Claude Code knows each model's own week, which the Claude app's file does not.
    private func askClaudeCode() {
        if provider == .claude { AgentClaudeCodeUsageService.shared.refreshIfStale(now: now) }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            NotchAgentMark(provider: provider, size: 12, tint: provider.tint)
                .frame(width: 14, height: 14)
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 2 }
            Text(provider.displayName)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.95))
            if let plan = snapshot.plans[provider] {
                Text(plan.name)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            if !snapshot.working(provider).isEmpty {
                NotchAgentPulse(tint: provider.tint, size: 5)
            }
            Spacer(minLength: 4)
            if let observed = snapshot.limits[provider]?.observedAt, now.timeIntervalSince(observed) > 600 {
                Text(text.updated(observed.formatted(.relative(presentation: .named, unitsStyle: .abbreviated)
                    .locale(locale))))
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
            }
        }
        .lineLimit(1)
        .frame(height: NotchAgentSupport.headerHeight)
    }

    /// What the window covers, how far it is spent, and when it renews.
    private func row(_ window: AgentLimitWindow) -> some View {
        let tint = agentLimitTint(provider, usedFraction: window.usedFraction)
        let remaining = display == .remaining
        let fraction = remaining ? window.remainingFraction : window.usedFraction
        let share = AgentFormat.percent(fraction)
        return NotchAgentUsageRow(title: label(window), caption: AgentLimitSupport.displayedReset(window, now: now)
            .map { resets(at: $0, estimated: window.estimatedResetsAt != nil) }) {
            NotchAgentMeter(value: fraction, tint: tint, height: 4)
            Text(remaining ? text.left(share) : text.usedShare(share))
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(tint == provider.tint ? AnyShapeStyle(.secondary) : AnyShapeStyle(tint))
                .contentTransition(.numericText())
                .frame(minWidth: 62, alignment: .trailing)
        }
    }

    private func label(_ window: AgentLimitWindow) -> String {
        switch window.kind {
        case .session: return text.currentSession
        // A model's own week reads by the model's name, as the account shows it.
        case .weekly: return window.scope ?? text.thisWeek
        case .other:
            guard let minutes = window.minutes else { return window.scope ?? text.readoutLimit }
            return AgentFormat.duration(TimeInterval(minutes) * 60, locale: locale, units: 1)
        }
    }

    /// "Resets 9:20 PM" today, "Resets Thu 11:00 PM" this week, a date after.
    private func resets(at date: Date, estimated: Bool) -> String {
        let calendar = Calendar.current
        let style: Date.FormatStyle
        if calendar.isDate(date, inSameDayAs: now) {
            style = .dateTime.hour().minute()
        } else if date.timeIntervalSince(now) < 6 * 86_400 {
            style = .dateTime.weekday(.abbreviated).hour().minute()
        } else {
            style = .dateTime.month(.abbreviated).day()
        }
        return text.resetsAt((estimated ? "≈ " : "") + date.formatted(style.locale(locale)))
    }

    /// Before the account reports its allowances: Claude's session still ends
    /// five hours after its first request, so that much is known.
    @ViewBuilder private var placeholder: some View {
        if provider == .claude, let block = snapshot.claudeBlock, block.end > now {
            NotchAgentUsageRow(title: text.currentSession, caption: resets(at: block.end, estimated: true)) {
                Spacer(minLength: 0)
                setUpLimits
            }
            .help(text.estimated)
        } else if provider == .claude {
            NotchAgentUsageRow(title: text.noSession, caption: nil) {
                Spacer(minLength: 0)
                setUpLimits
            }
        } else {
            NotchAgentUsageRow(title: text.waitingForLimits, caption: snapshot.lastActivity[provider].map {
                $0.formatted(.relative(presentation: .named, unitsStyle: .abbreviated).locale(locale))
            }, muted: true) { EmptyView() }
        }
    }

    /// Claude's plan limits come from the Claude app; the settings say how.
    private var setUpLimits: some View {
        Button {
            NotchService.shared.openSettings(showing: .agents)
        } label: {
            Text(text.claudeLimitsHint)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(provider.tint)
                .lineLimit(1)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A title over a quieter caption on the left, the reading on the right.
private struct NotchAgentUsageRow<Trailing: View>: View {
    let title: String
    let caption: String?
    var muted = false
    /// The column the title keeps, so meters line up; nil lets it fill the row.
    var textWidth: CGFloat? = 150
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(muted ? AnyShapeStyle(.secondary) : AnyShapeStyle(.white.opacity(0.9)))
                if let caption {
                    Text(caption)
                        .font(.system(size: 10))
                        .foregroundStyle(muted ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.secondary))
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .frame(width: textWidth, alignment: .leading)
            .frame(maxWidth: textWidth == nil ? .infinity : nil, alignment: .leading)
            trailing
        }
        .frame(height: NotchAgentSupport.rowHeight)
        .accessibilityElement(children: .combine)
    }
}

// MARK: Resets

/// Codex's banked resets: how many the account holds, when the next one
/// expires, and a use that asks first. Cancel takes the place of the button
/// that asked, so a double click never spends one.
private struct NotchAgentResetsRow: View {
    let now: Date
    let text: NotchAgentStrings
    @ObservedObject private var resets = AgentCodexResetService.shared
    @ObservedObject private var l10n = L10n.shared
    @State private var confirming = false
    @Environment(\.locale) private var locale

    private let tint = AgentProvider.codex.tint

    /// What a use did stays on the row for a minute.
    private var finished: AgentCodexResetService.Finished? {
        resets.finished.flatMap { now.timeIntervalSince($0.date) < 60 ? $0 : nil }
    }

    private var title: String {
        guard let available = resets.summary?.available, available > 0 else { return text.resetsCard }
        return "\(text.resetsCard) · \(available.formatted(.number.locale(locale)))"
    }

    var body: some View {
        NotchAgentUsageRow(title: title, caption: caption, muted: (resets.summary?.available ?? 0) == 0,
                           textWidth: nil) {
            buttons
        }
        .help(text.resetsHelp)
        .onAppear { resets.refreshIfStale() }
        // A count that changed while the question was open asks again.
        .onChange(of: resets.summary?.available) { _, _ in confirming = false }
    }

    private var caption: String? {
        if resets.redeeming { return text.resetting }
        if confirming, (resets.summary?.available ?? 0) > 0 { return text.resetConfirm }
        if let finished {
            switch finished.outcome {
            case .reset?: return text.resetDone
            case .nothingToReset?: return text.resetNotNeeded
            case .alreadyRedeemed?: return text.resetTaken
            case .noCredit?: return text.resetsNone
            case nil: return text.resetFailed
            }
        }
        if resets.summary == nil, let failure = resets.failure { return message(failure) }
        if let summary = resets.summary {
            guard summary.available > 0 else { return text.resetsNone }
            return summary.nextExpiry.map(expiry)
        }
        return nil
    }

    @ViewBuilder private var buttons: some View {
        if resets.redeeming || (resets.checking && resets.summary == nil) {
            ProgressView().controlSize(.mini)
        } else if confirming, let summary = resets.summary, summary.available > 0 {
            HStack(spacing: 6) {
                pill(FeatureStrings.clipboard(l10n.language).cancel, prominent: false) { confirming = false }
                pill(text.confirmReset) {
                    confirming = false
                    resets.redeem()
                }
            }
        } else if resets.summary == nil, let failure = resets.failure {
            pill(FeatureStrings.notchMusicExtras(l10n.language).retry, prominent: false) {
                resets.refresh(searchingShell: failure == .missing)
            }
        } else if let summary = resets.summary, summary.available > 0,
                  finished.map({ $0.outcome == nil }) ?? true {
            // Trying again repeats the same use, which never spends a second reset.
            pill(text.useReset) { confirming = true }
        }
    }

    private func expiry(_ date: Date) -> String {
        text.resetsExpiry(date.formatted(.relative(presentation: .named).locale(locale)))
    }

    private func message(_ failure: AgentCodexServer.Failure) -> String {
        switch failure {
        case .missing: return text.resetsNeedCodex
        case .needsSignIn: return text.resetsSignIn
        case .outdated: return text.resetsUpdate
        case .unreachable, .refused: return text.resetsCheckFailed
        }
    }

    private func pill(_ title: String, prominent: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .lineLimit(1)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(prominent ? 0.95 : 0.75))
                .padding(.horizontal, 11)
                .frame(height: 24)
                .background(.white.opacity(prominent ? 0.14 : 0.07),
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(NotchButtonStyle(cornerRadius: 7))
    }
}
