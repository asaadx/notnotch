// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// One line of the island's to-do list: a time of day and what to do then.
/// The time is minutes after midnight, with no date, so a list made for a
/// day reads the same the next morning.
struct NotchTask: Codable, Equatable, Identifiable {
    var id = UUID()
    var minutes: Int
    var text: String
    var done = false
}

/// The time of day as three wheels show it: an hour from 1 to 12, a minute
/// and a meridiem.
struct NotchTaskTime: Equatable {
    var hour: Int
    var minute: Int
    var pm: Bool

    init(hour: Int, minute: Int, pm: Bool) {
        self.hour = hour
        self.minute = minute
        self.pm = pm
    }

    init(minutes: Int) {
        let clamped = NotchTaskSupport.clampedMinutes(minutes)
        let hour24 = clamped / 60
        hour = hour24 % 12 == 0 ? 12 : hour24 % 12
        minute = clamped % 60
        pm = hour24 >= 12
    }

    var minutes: Int {
        let hour24 = (min(12, max(1, hour)) % 12) + (pm ? 12 : 0)
        return hour24 * 60 + min(59, max(0, minute))
    }
}

enum NotchTaskSupport {
    static let maximumCount = 40
    static let maximumTextLength = 120
    static let fileName = "Tasks.json"
    private static let day = 24 * 60

    static func clampedMinutes(_ minutes: Int) -> Int {
        min(day - 1, max(0, minutes))
    }

    /// The list's own short form, lowercase and without a space: "5pm",
    /// "12am", "9:30am". Whole hours drop their minutes.
    static func timeLabel(_ minutes: Int) -> String {
        let time = NotchTaskTime(minutes: minutes)
        let meridiem = time.pm ? "pm" : "am"
        return time.minute == 0
            ? "\(time.hour)\(meridiem)"
            : "\(time.hour):" + String(format: "%02d", time.minute) + meridiem
    }

    /// "5pm — gym": the whole row as it reads, lowercase throughout.
    static func rowText(_ task: NotchTask) -> String {
        timeLabel(task.minutes) + " — " + displayText(task.text)
    }

    static func displayText(_ text: String) -> String {
        text.lowercased()
    }

    /// One line, trimmed and bounded; nil when nothing is left to keep.
    static func sanitizedText(_ text: String) -> String? {
        let line = text.components(separatedBy: .newlines).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty else { return nil }
        return String(line.prefix(maximumTextLength))
    }

    /// What comes after a task just added: half an hour later.
    static let followingInterval = 30

    static func followingMinutes(after minutes: Int) -> Int {
        (clampedMinutes(minutes) + followingInterval) % day
    }

    /// The next task follows the list's last task by time, not the one just
    /// added; nil for an empty list.
    static func followingMinutes(after tasks: [NotchTask]) -> Int? {
        tasks.map(\.minutes).max().map { followingMinutes(after: $0) }
    }

    /// The list as it reads: by time of day, with tasks at the same time in
    /// the order they were added. Finishing one never moves it.
    static func ordered(_ tasks: [NotchTask]) -> [NotchTask] {
        tasks.enumerated()
            .sorted { ($0.element.minutes, $0.offset) < ($1.element.minutes, $1.offset) }
            .map(\.element)
    }

    /// A time typed by hand: "8", "8pm", "8:30p", "830pm", "20:30" or
    /// "2030". An hour of 1 to 12 without a meridiem keeps `pm`, the one the
    /// drums show. Nil when it is not a time.
    static func parseTime(_ text: String, pm: Bool) -> Int? {
        var rest = text.lowercased().filter { !$0.isWhitespace }
        var meridiem: Bool?
        for (suffix, isPM) in [("am", false), ("pm", true), ("a", false), ("p", true)] where rest.hasSuffix(suffix) {
            meridiem = isPM
            rest.removeLast(suffix.count)
            break
        }
        let hourText: Substring
        let minuteText: Substring
        if let separator = rest.firstIndex(where: { $0 == ":" || $0 == "." }) {
            hourText = rest[..<separator]
            minuteText = rest[rest.index(after: separator)...]
            guard minuteText.count == 2 else { return nil }
        } else if rest.count <= 2 {
            hourText = Substring(rest)
            minuteText = "0"
        } else if rest.count <= 4 {
            hourText = rest.dropLast(2)
            minuteText = rest.suffix(2)
        } else {
            return nil
        }
        guard !hourText.isEmpty, hourText.allSatisfy(\.isASCII), minuteText.allSatisfy(\.isASCII),
              let hour = Int(hourText), let minute = Int(minuteText), (0..<60).contains(minute) else { return nil }
        if let meridiem {
            guard (1...12).contains(hour) else { return nil }
            return NotchTaskTime(hour: hour, minute: minute, pm: meridiem).minutes
        }
        if (1...12).contains(hour) { return NotchTaskTime(hour: hour, minute: minute, pm: pm).minutes }
        guard (0..<24).contains(hour) else { return nil }
        return hour * 60 + minute
    }

    /// How late a reminder may still arrive, after sleep or a busy moment;
    /// anything older stays quiet.
    static let reminderGrace: TimeInterval = 15 * 60
    static let reminderPrefix = "com.vorssaint.notch-task."

    /// The task's time on the day of `date`.
    static func occurrence(of minutes: Int, onDayOf date: Date, calendar: Calendar = .current) -> Date? {
        let minutes = clampedMinutes(minutes)
        return calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: date)
    }

    /// Tasks still to do whose time came up after `from`, until `to`.
    static func dueTasks(_ tasks: [NotchTask], from: Date, to: Date, calendar: Calendar = .current) -> [NotchTask] {
        ordered(tasks).filter { task in
            guard !task.done, var at = occurrence(of: task.minutes, onDayOf: to, calendar: calendar) else { return false }
            if at > to { at = calendar.date(byAdding: .day, value: -1, to: at) ?? at }
            return at > from && at <= to
        }
    }

    /// When a task still to do next comes up after `date`, on that day or
    /// the next.
    static func nextReminder(_ tasks: [NotchTask], after date: Date, calendar: Calendar = .current) -> Date? {
        tasks.filter { !$0.done }.compactMap { task -> Date? in
            guard let today = occurrence(of: task.minutes, onDayOf: date, calendar: calendar) else { return nil }
            return today > date ? today : calendar.date(byAdding: .day, value: 1, to: today)
        }.min()
    }

    /// The next whole hour, so a new task starts somewhere sensible.
    static func suggestedMinutes(now: Date, calendar: Calendar = .current) -> Int {
        let parts = calendar.dateComponents([.hour], from: now)
        return ((parts.hour ?? 8) + 1) % 24 * 60
    }

    /// Whatever was written by hand or by an older version comes back in
    /// bounds; rows keep the order they were stored in.
    static func sanitized(_ tasks: [NotchTask]) -> [NotchTask] {
        var seen = Set<UUID>()
        return tasks.compactMap { task -> NotchTask? in
            guard seen.insert(task.id).inserted, let text = sanitizedText(task.text) else { return nil }
            var task = task
            task.text = text
            task.minutes = clampedMinutes(task.minutes)
            return task
        }
        .prefix(maximumCount).map { $0 }
    }
}

/// The list on disk, beside the scratchpad in the app's private container.
/// A failed read never authorizes a save, so an unreadable file is left for
/// the user rather than overwritten with an empty list.
struct NotchTaskStore {
    let directoryURL: URL?
    private(set) var canSave = false

    init(directoryURL: URL?) {
        self.directoryURL = directoryURL
    }

    mutating func load() throws -> [NotchTask] {
        canSave = false
        guard let directoryURL else { throw CocoaError(.fileReadUnknown) }
        let url = directoryURL.appendingPathComponent(NotchTaskSupport.fileName)
        let tasks: [NotchTask]
        do {
            tasks = try JSONDecoder().decode([NotchTask].self, from: Data(contentsOf: url))
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            tasks = []
        }
        canSave = true
        return NotchTaskSupport.sanitized(tasks)
    }

    func save(_ tasks: [NotchTask]) -> Bool {
        guard canSave, let directoryURL, let data = try? JSONEncoder().encode(tasks) else { return false }
        return PrivateFileStore.createDirectory(at: directoryURL)
            && PrivateFileStore.write(data, to: directoryURL.appendingPathComponent(NotchTaskSupport.fileName))
    }
}
