// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

extension AgentProvider {
    /// Each agent keeps one color across the page, the strip and notices.
    var tint: Color {
        switch self {
        case .claude: return Color(red: 0.85, green: 0.47, blue: 0.34)
        case .codex: return Color(red: 0.49, green: 0.60, blue: 1.0)
        case .opencode: return Color(red: 0.06, green: 0.73, blue: 0.51)
        case .copilot: return Color(red: 0.30, green: 0.78, blue: 0.68)
        }
    }
}

/// Green reads as fine and red as trouble only when it earns it: the agent's
/// own color while there is room, orange once a window runs low.
func agentLimitTint(_ provider: AgentProvider, usedFraction: Double) -> Color {
    if usedFraction >= 0.95 { return .red }
    if usedFraction >= 0.8 { return .orange }
    return provider.tint
}

/// A capsule meter with a tick where spending would be if it were spread
/// evenly across the window: a fill past the tick is ahead of pace.
struct NotchAgentMeter: View {
    let value: Double
    var pace: Double?
    var tint: Color = .white
    var height: CGFloat = 5
    var dimmed = false

    var body: some View {
        let fraction = value.isFinite ? min(1, max(0, value)) : 0
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous).fill(.white.opacity(0.13))
                Capsule(style: .continuous)
                    .fill(tint.opacity(dimmed ? 0.45 : 0.92))
                    .frame(width: max(fraction > 0 ? height : 0, proxy.size.width * fraction))
                if let pace, pace.isFinite, pace > 0.02, pace < 0.98 {
                    RoundedRectangle(cornerRadius: 0.75)
                        .fill(.white.opacity(0.85))
                        .frame(width: 1.5, height: height + 5)
                        .offset(x: proxy.size.width * pace - 0.75)
                }
            }
            .frame(height: proxy.size.height)
        }
        .frame(height: height + 5)
        .accessibilityHidden(true)
    }
}

/// A small ring for the closed island, filled by what is left.
struct NotchAgentRing: View {
    let value: Double
    var tint: Color = .white
    var lineWidth: CGFloat = 2.5

    var body: some View {
        let fraction = value.isFinite ? min(1, max(0, value)) : 0
        ZStack {
            Circle().stroke(.white.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .accessibilityHidden(true)
    }
}

/// A calm pulse that says an agent is working; still under Reduce Motion.
/// Native layer motion avoids driving the surrounding SwiftUI graph at the
/// display refresh rate, including Settings previews retained after closing.
struct NotchAgentPulse: View {
    var tint: Color
    var size: CGFloat = 6
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NotchAgentPulseBridge(tint: NSColor(tint), size: size, animates: !reduceMotion)
            .frame(width: size * 2, height: size * 2)
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }
}

/// The agent's mark breathing while it works. A turn would read as a
/// cross halfway round, so the mark keeps its angle.
struct NotchAgentGlyph: View {
    let provider: AgentProvider
    var size: CGFloat = 13
    var working = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NotchAgentGlyphBridge(provider: provider, size: size, animates: working && !reduceMotion)
            // Room for the marks, drawn past their size.
            .frame(width: size * 1.45 + 1, height: size * 1.45 + 1)
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }
}

private struct NotchAgentPulseBridge: NSViewRepresentable {
    let tint: NSColor
    let size: CGFloat
    let animates: Bool

    func makeNSView(context: Context) -> NotchAgentAnimationView { NotchAgentAnimationView() }
    func updateNSView(_ view: NotchAgentAnimationView, context: Context) {
        view.configurePulse(size: size, tint: tint, animates: animates)
    }
    static func dismantleNSView(_ view: NotchAgentAnimationView, coordinator: ()) { view.stop() }
}

private struct NotchAgentGlyphBridge: NSViewRepresentable {
    let provider: AgentProvider
    let size: CGFloat
    let animates: Bool

    func makeNSView(context: Context) -> NotchAgentAnimationView { NotchAgentAnimationView() }
    func updateNSView(_ view: NotchAgentAnimationView, context: Context) {
        let image: NSImage?
        let markSize: CGFloat
        let tint: NSColor?
        switch AgentMarks.mark(for: provider) {
        case .template(let mark):
            image = mark
            markSize = size * provider.markScale
            tint = NSColor(provider.tint)
        case .icon(let mark):
            image = mark
            markSize = size * 1.35
            tint = nil
        case nil:
            image = NSImage(systemSymbolName: provider.symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: size, weight: .semibold))
            markSize = size
            tint = NSColor(provider.tint)
        }
        // Claude's spark holds still and shimmers; a swelling spark read as a distraction.
        view.configureGlyph(image: image, size: markSize, tint: tint, animates: animates,
                            shimmers: provider == .claude)
    }
    static func dismantleNSView(_ view: NotchAgentAnimationView, coordinator: ()) { view.stop() }
}

/// Each agent's own mark. Claude Code and Codex ship theirs with Vorssaint
/// (from Lobe Icons, MIT), since their makers' apps show other products'
/// marks. The rest come from the maker's app on this Mac: the monochrome
/// image it shows in the menu bar, or else its icon, and a Mac without the
/// app keeps a symbol. Looked up once; the strip redraws every second.
enum AgentMarks {
    enum Mark {
        /// Drawn in the agent's color, like the symbol it replaces.
        case template(NSImage)
        case icon(NSImage)
    }

    private static var found: [AgentProvider: Mark?] = [:]

    static func mark(for provider: AgentProvider) -> Mark? {
        if let mark = found[provider] { return mark }
        let mark = lookUp(provider)
        found[provider] = .some(mark)
        return mark
    }

    private static func lookUp(_ provider: AgentProvider) -> Mark? {
        if let name = provider.bundledMarkName,
           let url = Bundle.main.url(forResource: name, withExtension: "svg", subdirectory: "Images"),
           let image = NSImage(contentsOf: url) {
            image.isTemplate = true
            return .template(image)
        }
        for identifier in provider.appIdentifiers {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) else { continue }
            if let bundle = Bundle(url: url) {
                for name in provider.menuBarImageNames {
                    if let image = bundle.image(forResource: name) {
                        image.isTemplate = true
                        return .template(image)
                    }
                }
            }
            return .icon(NSWorkspace.shared.icon(forFile: url.path))
        }
        return nil
    }
}

private extension AgentProvider {
    /// The maker's desktop apps, the one that runs the agent first.
    var appIdentifiers: [String] {
        switch self {
        case .claude: return [AgentClaudeAppUsage.bundleIdentifier]
        case .codex: return AgentCodexServer.appIdentifiers
        case .opencode: return ["ai.opencode.desktop", "ai.opencode.desktop.beta", "ai.opencode.desktop.dev"]
        case .copilot: return ["com.github.githubapp"]
        }
    }

    /// The mark Vorssaint carries itself, in Resources/Images.
    var bundledMarkName: String? {
        switch self {
        case .claude: return "agent-claude-code"
        case .codex: return "agent-codex"
        case .opencode, .copilot: return nil
        }
    }

    /// The marks keep a margin in their box, so they draw past the symbol's size.
    var markScale: CGFloat { 1.2 }

    /// What those apps name the mark they show in the menu bar.
    var menuBarImageNames: [String] {
        switch self {
        case .claude: return ["TrayIconTemplate"]
        case .codex: return ["chatgptTemplate"]
        // The OpenCode app shows nothing in the menu bar; its icon stands in.
        case .opencode: return []
        case .copilot: return []
        }
    }
}

/// An agent's mark at the size of the symbol it stands in for.
struct NotchAgentMark: View {
    let provider: AgentProvider
    var size: CGFloat = 13
    var tint: Color?

    var body: some View {
        switch AgentMarks.mark(for: provider) {
        case .template(let image):
            Image(nsImage: image)
                .renderingMode(.template)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: size * provider.markScale, height: size * provider.markScale)
                .foregroundStyle(tint ?? provider.tint)
        case .icon(let image):
            // App icons keep a margin around their artwork.
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: size * 1.35, height: size * 1.35)
        case nil:
            Image(systemName: provider.symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(tint ?? provider.tint)
        }
    }
}
