// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The list's row format, its wheel arithmetic and its file on disk, in a
/// temporary directory.
enum NotchTaskTests {
    static func run(_ suite: TestSuite) {
        suite.expect(NotchTaskSupport.timeLabel(17 * 60) == "5pm", "a whole hour reads without minutes or a space")
        suite.expect(NotchTaskSupport.timeLabel(9 * 60 + 5) == "9:05am", "minutes keep two digits")
        suite.expect(NotchTaskSupport.timeLabel(0) == "12am" && NotchTaskSupport.timeLabel(12 * 60) == "12pm",
                     "midnight and noon read as twelve")
        suite.expect(NotchTaskSupport.rowText(NotchTask(minutes: 17 * 60, text: "Gym")) == "5pm — gym",
                     "a row reads time, em dash, task, all lowercase")

        for minutes in [0, 59, 60, 719, 720, 721, 1439] {
            suite.expect(NotchTaskTime(minutes: minutes).minutes == minutes, "the wheels round-trip \(minutes)")
        }
        suite.expect(NotchTaskTime(hour: 12, minute: 0, pm: false).minutes == 0, "12am is midnight")
        suite.expect(NotchTaskTime(minutes: 5000).minutes == 1439, "an out-of-range time is clamped")

        suite.expect(NotchTaskSupport.sanitizedText("  \n ") == nil, "a blank task is not kept")
        suite.expect(NotchTaskSupport.sanitizedText(" call\nmom ") == "call mom", "a task stays on one line")

        let done = NotchTask(minutes: 600, text: "b", done: true)
        let duplicate = NotchTask(id: done.id, minutes: 60, text: "dup")
        let ordered = NotchTaskSupport.sanitized([NotchTask(minutes: 1200, text: "a"), done, duplicate,
                                                  NotchTask(minutes: 60, text: "c")])
        suite.expect(ordered.map(\.text) == ["a", "b", "c"], "stored order is kept, finished rows included")

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("notch-tasks-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var unloaded = NotchTaskStore(directoryURL: root)
        suite.expect(!unloaded.save(ordered), "nothing is written before a read succeeds")
        suite.expect((try? unloaded.load()) == [], "a missing file is an empty list")
        suite.expect(unloaded.save(ordered), "the list saves after a read")
        var restarted = NotchTaskStore(directoryURL: root)
        suite.expect((try? restarted.load()) == ordered, "the list comes back after a restart")

        try? Data("not json".utf8).write(to: root.appendingPathComponent(NotchTaskSupport.fileName))
        var corrupt = NotchTaskStore(directoryURL: root)
        suite.expect((try? corrupt.load()) == nil && !corrupt.save([]), "an unreadable file is never overwritten")
    }
}
