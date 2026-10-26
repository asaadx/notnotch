// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The card a sticky note is written on, in the order new notes take them.
enum NotchStickyColor: String, Codable, CaseIterable {
    case sky, mint, lilac, lemon, rose, peach
}

/// One sticky note: a few lines on coloured card, named by the first
/// of them.
struct NotchSticky: Codable, Equatable, Identifiable {
    var id = UUID()
    var text: String
    var color: NotchStickyColor

    init(id: UUID = UUID(), text: String = "", color: NotchStickyColor) {
        self.id = id
        self.text = text
        self.color = color
    }

    /// A colour a later version adds reads as lemon here rather than
    /// losing the note.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        color = (try? container.decode(NotchStickyColor.self, forKey: .color)) ?? .lemon
    }
}

enum NotchStickySupport {
    static let maximumCount = 30
    static let maximumTextLength = 800
    /// Typing is written this long after it pauses.
    static let saveDelay: TimeInterval = 0.25
    static let fileName = "StickyNotes.json"

    /// New notes take the colours in turn, so neighbours rarely match.
    static func nextColor(after notes: [NotchSticky]) -> NotchStickyColor {
        let colors = NotchStickyColor.allCases
        guard let latest = notes.last?.color, let index = colors.firstIndex(of: latest) else { return colors[0] }
        return colors[(index + 1) % colors.count]
    }

    /// What a note is called: its first written line.
    static func label(_ note: NotchSticky) -> String? {
        note.text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
    }

    /// Lines are kept as written; only the trailing blank space goes, and
    /// the length is capped.
    static func sanitizedText(_ text: String) -> String {
        var trimmed = String(text.prefix(maximumTextLength))
        while let last = trimmed.last, last.isWhitespace { trimmed.removeLast() }
        return trimmed
    }

    static func isBlank(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func isBlank(_ note: NotchSticky) -> Bool {
        isBlank(note.text)
    }

    /// Whatever was written by hand or by an older version comes back in
    /// bounds; blank notes are let go and the rest keep their order.
    static func sanitized(_ notes: [NotchSticky]) -> [NotchSticky] {
        var seen = Set<UUID>()
        return notes.compactMap { note -> NotchSticky? in
            guard seen.insert(note.id).inserted, !isBlank(note) else { return nil }
            var note = note
            note.text = sanitizedText(note.text)
            return note
        }
        .prefix(maximumCount).map { $0 }
    }
}

/// The notes on disk, beside the tasks in the app's private container. A
/// failed read never authorizes a save, so an unreadable file is left for
/// the user rather than overwritten with no notes.
struct NotchStickyStore {
    let directoryURL: URL?
    private(set) var canSave = false

    init(directoryURL: URL?) {
        self.directoryURL = directoryURL
    }

    mutating func load() throws -> [NotchSticky] {
        canSave = false
        guard let directoryURL else { throw CocoaError(.fileReadUnknown) }
        let url = directoryURL.appendingPathComponent(NotchStickySupport.fileName)
        let notes: [NotchSticky]
        do {
            notes = try JSONDecoder().decode([NotchSticky].self, from: Data(contentsOf: url))
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            notes = []
        }
        canSave = true
        return NotchStickySupport.sanitized(notes)
    }

    func save(_ notes: [NotchSticky]) -> Bool {
        guard canSave, let directoryURL, let data = try? JSONEncoder().encode(notes) else { return false }
        return PrivateFileStore.createDirectory(at: directoryURL)
            && PrivateFileStore.write(data, to: directoryURL.appendingPathComponent(NotchStickySupport.fileName))
    }
}
