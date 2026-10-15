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

        suite.expect(NotchTaskSupport.followingMinutes(after: 20 * 60) == 20 * 60 + 30,
                     "the next task is half an hour after the last one")
        suite.expect(NotchTaskSupport.followingMinutes(after: 23 * 60 + 45) == 15, "the next time wraps past midnight")
        suite.expect(NotchTaskSupport.followingMinutes(after: [NotchTask(minutes: 21 * 60, text: "late"),
                                                               NotchTask(minutes: 9 * 60, text: "early")]) == 21 * 60 + 30,
                     "the next task follows the latest one, not the one added last")
        suite.expect(NotchTaskSupport.followingMinutes(after: [NotchTask]()) == nil, "an empty list suggests nothing")

        let gym = NotchTask(minutes: 22 * 60, text: "gym")
        let dinner = NotchTask(minutes: 21 * 60, text: "dinner", done: true)
        let call = NotchTask(minutes: 22 * 60, text: "call")
        suite.expect(NotchTaskSupport.ordered([gym, dinner, call]).map(\.text) == ["dinner", "gym", "call"],
                     "rows read by time, ties in the order they were added, finished rows in place")

        let parses: [(String, Bool, Int?)] = [
            ("8pm", false, 20 * 60), ("8:30p", false, 20 * 60 + 30), ("830pm", false, 20 * 60 + 30),
            ("8 30 am", true, 8 * 60 + 30), ("20:30", false, 20 * 60 + 30), ("2030", false, 20 * 60 + 30),
            ("0", false, 0), ("12am", true, 0), ("12pm", false, 12 * 60), ("8", true, 20 * 60), ("8", false, 8 * 60),
            ("8:5pm", false, nil), ("13pm", false, nil), ("24", false, nil), ("8:60", false, nil),
            ("", false, nil), ("pm", false, nil), ("gym", false, nil), ("12345", false, nil)]
        for (input, pm, expected) in parses {
            suite.expect(NotchTaskSupport.parseTime(input, pm: pm) == expected, "\"\(input)\" parses to \(String(describing: expected))")
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let day = Date(timeIntervalSince1970: 1_700_000_000)
        func at(_ minutes: Int, days: Int = 0) -> Date {
            calendar.date(byAdding: .day, value: days,
                          to: NotchTaskSupport.occurrence(of: minutes, onDayOf: day, calendar: calendar)!)!
        }
        let reminded = [NotchTask(minutes: 17 * 60, text: "gym"), NotchTask(minutes: 9 * 60, text: "walk", done: true),
                        NotchTask(minutes: 8 * 60, text: "coffee")]
        suite.expect(NotchTaskSupport.nextReminder(reminded, after: at(12 * 60), calendar: calendar) == at(17 * 60),
                     "the next reminder is the next task still to do today")
        suite.expect(NotchTaskSupport.nextReminder(reminded, after: at(18 * 60), calendar: calendar) == at(8 * 60, days: 1),
                     "after the last one, the next is tomorrow's first; a finished task is skipped")
        suite.expect(NotchTaskSupport.nextReminder([], after: at(0), calendar: calendar) == nil, "no tasks, no reminder")
        suite.expect(NotchTaskSupport.dueTasks(reminded, from: at(16 * 60 + 59), to: at(17 * 60), calendar: calendar)
                        .map(\.text) == ["gym"], "a reminder is due once its time arrives")
        suite.expect(NotchTaskSupport.dueTasks(reminded, from: at(17 * 60), to: at(17 * 60 + 1), calendar: calendar).isEmpty,
                     "a reminder already given is not given again")
        suite.expect(NotchTaskSupport.dueTasks(reminded, from: at(8 * 60 + 50), to: at(9 * 60 + 5), calendar: calendar).isEmpty,
                     "a finished task is never due")
        suite.expect(NotchTaskSupport.dueTasks(reminded, from: at(23 * 60 + 55, days: -1), to: at(8 * 60 + 5), calendar: calendar)
                        .map(\.text) == ["coffee"], "a check across midnight finds the morning's task")

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
