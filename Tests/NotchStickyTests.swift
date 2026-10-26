// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The sticky notes' colours, labels, text and file on disk, in a
/// temporary directory.
enum NotchStickyTests {
    static func run(_ suite: TestSuite) {
        suite.expect(NotchStickySupport.nextColor(after: []) == .sky, "the first note is sky")
        suite.expect(NotchStickySupport.nextColor(after: [NotchSticky(text: "a", color: .peach)]) == .sky,
                     "colours are dealt in turn and wrap around")
        suite.expect(NotchStickySupport.nextColor(after: [NotchSticky(text: "a", color: .lemon),
                                                          NotchSticky(text: "b", color: .sky)]) == .mint,
                     "the next colour follows the newest note")

        suite.expect(NotchStickySupport.label(NotchSticky(text: "\n  call mom \nlater", color: .mint)) == "call mom",
                     "a note is named by its first written line")
        suite.expect(NotchStickySupport.label(NotchSticky(color: .mint)) == nil, "a blank note has no name")

        suite.expect(NotchStickySupport.sanitizedText("milk\neggs  \n\n") == "milk\neggs", "lines stay, trailing space goes")
        suite.expect(NotchStickySupport.sanitizedText(String(repeating: "x", count: 5000)).count
                        == NotchStickySupport.maximumTextLength, "a note's length is capped")

        let first = NotchSticky(text: "one", color: .lemon)
        let duplicate = NotchSticky(id: first.id, text: "dup", color: .sky)
        let blank = NotchSticky(text: " \n ", color: .rose)
        let second = NotchSticky(text: "two", color: .mint)
        let notes = NotchStickySupport.sanitized([first, duplicate, blank, second])
        suite.expect(notes.map(\.id) == [first.id, second.id], "blank and repeated notes are let go, order kept")

        let older = Data(#"[{"id":"\#(UUID().uuidString)","text":"hi","color":"tangerine"}]"#.utf8)
        suite.expect((try? JSONDecoder().decode([NotchSticky].self, from: older))?.first?.color == .lemon,
                     "a note in an unknown colour still reads")

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("notch-stickies-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var unloaded = NotchStickyStore(directoryURL: root)
        suite.expect(!unloaded.save(notes), "nothing is written before a read succeeds")
        suite.expect((try? unloaded.load()) == [], "a missing file is no notes")
        suite.expect(unloaded.save(notes), "the notes save after a read")
        var restarted = NotchStickyStore(directoryURL: root)
        suite.expect((try? restarted.load()) == notes, "the notes come back after a restart")

        try? Data("not json".utf8).write(to: root.appendingPathComponent(NotchStickySupport.fileName))
        var corrupt = NotchStickyStore(directoryURL: root)
        suite.expect((try? corrupt.load()) == nil && !corrupt.save([]), "an unreadable file is never overwritten")
    }
}
