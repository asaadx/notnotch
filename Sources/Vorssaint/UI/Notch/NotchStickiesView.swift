// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// Sticky notes in the island: flat pastel cards, three to a row, each
/// reading its first line in bold above the rest. Clicking a card opens it
/// across the page to write on, with its colours and a bin along the foot;
/// the tick or Escape puts it back, and a card left blank goes.
/// The plus card first in the grid adds a note in the next colour.
struct NotchStickiesView: View {
    @ObservedObject var service: NotchService
    @ObservedObject private var stickies = NotchStickyService.shared
    @ObservedObject private var l10n = L10n.shared
    @State private var openID: UUID?
    @FocusState private var writing: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.notchSettingsPreview) private var preview
    private var text: NotchStickyStrings { FeatureStrings.notchStickies(l10n.language) }

    private static let cardHeight: CGFloat = 104
    private static let spacing: CGFloat = 8
    private static let columns = Array(repeating: GridItem(.flexible(), spacing: spacing), count: 3)

    private var animation: Animation? {
        reduceMotion ? nil : .smooth(duration: 0.22)
    }

    var body: some View {
        Group {
            if stickies.loadFailed {
                NotchEmptyView(symbol: "exclamationmark.triangle", message: text.loadFailed) { EmptyView() }
            } else if let id = openID, let note = stickies.notes.first(where: { $0.id == id }) {
                editor(note)
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            } else {
                grid.transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { stickies.load() }
        .onChange(of: openID) { _, id in report(id != nil) }
        .onDisappear {
            if let openID { stickies.finish(openID) }
            openID = nil
            guard !preview else { return }
            stickies.editing = false
            service.setPageLayer(.stickies, close: nil)
        }
    }

    /// An open card keeps the island open, and Escape puts it back before
    /// it closes the island.
    private func report(_ active: Bool) {
        guard !preview else { return }
        stickies.editing = active
        service.setPageLayer(.stickies, close: active ? { close() } : nil)
    }

    // MARK: - Grid

    private var grid: some View {
        VStack(spacing: 6) {
            ScrollView(.vertical) {
                LazyVGrid(columns: Self.columns, spacing: Self.spacing) {
                    addCard
                    // Newest first, after the plus card.
                    ForEach(stickies.notes.reversed()) { card($0) }
                }
            }
            .scrollIndicators(.never)
            .notchScrollEdgeFade()
            if stickies.saveFailed {
                Label(text.saveFailed, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 10.5)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var addCard: some View {
        Button(action: add) {
            VStack(spacing: 6) {
                Image(systemName: "plus").font(.system(size: 16, weight: .medium))
                Text(stickies.canAdd ? text.newNote : String(format: text.limitFormat, NotchStickySupport.maximumCount))
                    .font(.system(size: 11, weight: .medium))
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(.white.opacity(0.6))
            .frame(maxWidth: .infinity)
            .frame(height: Self.cardHeight)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(NotchButtonStyle(cornerRadius: 12, lifts: false))
        .modifier(NotchControlSurface(cornerRadius: 12, interactive: false))
        .disabled(!stickies.canAdd)
        .keyboardShortcut("n", modifiers: .command)
        .accessibilityLabel(text.newNote)
    }

    private func card(_ note: NotchSticky) -> some View {
        Button { open(note.id) } label: {
            noteText(note)
                .font(.system(size: 12))
                .foregroundStyle(StickyStyle.ink)
                .lineLimit(6)
                .padding(10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .frame(height: Self.cardHeight)
                .background(StickyStyle.fill(note.color), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(NotchButtonStyle(cornerRadius: 12, highlights: false))
        .contextMenu {
            Button(text.delete, role: .destructive) { delete(note.id) }
        }
        .accessibilityLabel(NotchStickySupport.label(note) ?? text.untitled)
        .accessibilityValue(note.text)
    }

    /// The first line in bold, the rest as written.
    private func noteText(_ note: NotchSticky) -> Text {
        let trimmed = note.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let split = trimmed.firstIndex(where: \.isNewline) else { return Text(trimmed).fontWeight(.semibold) }
        return Text(trimmed[..<split]).fontWeight(.semibold) + Text("\n") + Text(trimmed[trimmed.index(after: split)...])
    }

    // MARK: - Writing

    private func editor(_ note: NotchSticky) -> some View {
        let words = Binding(get: { stickies.notes.first { $0.id == note.id }?.text ?? "" },
                            set: { stickies.update(note.id, text: $0) })
        return VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                if note.text.isEmpty {
                    Text(text.placeholder)
                        .foregroundStyle(StickyStyle.ink.opacity(0.4))
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
                TextEditor(text: words)
                    .foregroundStyle(StickyStyle.ink)
                    .tint(StickyStyle.ink)
                    .scrollContentBackground(.hidden)
                    .scrollIndicators(.never)
                    .focused($writing)
                    .accessibilityLabel(text.title)
            }
            .font(.system(size: 14))
            HStack(spacing: 6) {
                ForEach(NotchStickyColor.allCases, id: \.self) { color in
                    let selected = note.color == color
                    Button { stickies.setColor(note.id, color) } label: {
                        Circle()
                            .fill(StickyStyle.fill(color))
                            .overlay { Circle().strokeBorder(StickyStyle.ink.opacity(selected ? 0.6 : 0.12),
                                                             lineWidth: selected ? 1.5 : 1) }
                            .frame(width: 14, height: 14)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help(text.name(of: color))
                    .accessibilityLabel(text.name(of: color))
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
                Spacer(minLength: 4)
                Button { delete(note.id) } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(StickyStyle.ink.opacity(0.55))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(text.delete)
                .accessibilityLabel(text.delete)
                Button(action: close) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(StickyStyle.ink.opacity(0.75))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.return, modifiers: .command)
                .help(text.done)
                .accessibilityLabel(text.done)
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(StickyStyle.fill(note.color), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .animation(animation, value: note.color)
        .onAppear { DispatchQueue.main.async { writing = true } }
    }

    // MARK: - Actions

    private func add() {
        guard let id = stickies.add() else { return }
        withAnimation(animation) { openID = id }
    }

    private func open(_ id: UUID) {
        withAnimation(animation) { openID = id }
    }

    private func close() {
        guard let id = openID else { return }
        writing = false
        withAnimation(animation) {
            openID = nil
            stickies.finish(id)
        }
    }

    private func delete(_ id: UUID) {
        if openID == id { writing = false }
        withAnimation(animation) {
            if openID == id { openID = nil }
            stickies.delete(id)
        }
    }
}

/// The notes' ink and card colours.
enum StickyStyle {
    static var ink: Color { Color(red: 0.12, green: 0.13, blue: 0.14) }

    static func fill(_ color: NotchStickyColor) -> Color {
        switch color {
        case .sky: return Color(red: 0.71, green: 0.84, blue: 0.99)
        case .mint: return Color(red: 0.71, green: 0.89, blue: 0.82)
        case .lilac: return Color(red: 0.84, green: 0.80, blue: 0.99)
        case .lemon: return Color(red: 0.98, green: 0.85, blue: 0.49)
        case .rose: return Color(red: 0.99, green: 0.77, blue: 0.83)
        case .peach: return Color(red: 0.99, green: 0.81, blue: 0.67)
        }
    }
}
