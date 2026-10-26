// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// A Todoist due date as the Sync API writes it: a day ("2026-10-16"), a
/// floating time ("2026-10-16T17:00:00.000000") or a fixed one in UTC
/// ("2026-10-16T21:00:00.000000Z"). The same keys are kept on disk.
struct NotchTodoistDue: Codable, Equatable {
    var date: String
    var timezone: String?
    var string: String?
    var isRecurring = false

    private enum CodingKeys: String, CodingKey {
        case date, timezone, string
        case isRecurring = "is_recurring"
    }

    init(date: String, timezone: String? = nil, string: String? = nil, isRecurring: Bool = false) {
        self.date = date
        self.timezone = timezone
        self.string = string
        self.isRecurring = isRecurring
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        date = try container.decode(String.self, forKey: .date)
        timezone = try container.decodeIfPresent(String.self, forKey: .timezone)
        string = try container.decodeIfPresent(String.self, forKey: .string)
        isRecurring = try container.decodeIfPresent(Bool.self, forKey: .isRecurring) ?? false
    }
}

/// The Todoist task a row of the list mirrors: its id (a temporary one until
/// Todoist acknowledges a task added here), the day the row is shown for and
/// that day's due date, which undoes a repeating task finished by mistake.
struct NotchTodoistLink: Codable, Equatable {
    var id: String
    var day: String
    var due: NotchTodoistDue
}

/// A task as the Sync API returns it, with only what the list reads.
struct NotchTodoistItem: Decodable, Equatable {
    var id: String
    var content: String
    var checked = false
    var isDeleted = false
    var due: NotchTodoistDue?
    var responsibleUID: String?
    var dayOrder: Int?

    private enum CodingKeys: String, CodingKey {
        case id, content, checked, due
        case isDeleted = "is_deleted"
        case responsibleUID = "responsible_uid"
        case dayOrder = "day_order"
    }

    init(id: String, content: String, checked: Bool = false, isDeleted: Bool = false, due: NotchTodoistDue? = nil,
         responsibleUID: String? = nil, dayOrder: Int? = nil) {
        self.id = id
        self.content = content
        self.checked = checked
        self.isDeleted = isDeleted
        self.due = due
        self.responsibleUID = responsibleUID
        self.dayOrder = dayOrder
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        content = try container.decodeIfPresent(String.self, forKey: .content) ?? ""
        checked = try container.decodeIfPresent(Bool.self, forKey: .checked) ?? false
        isDeleted = try container.decodeIfPresent(Bool.self, forKey: .isDeleted) ?? false
        due = try container.decodeIfPresent(NotchTodoistDue.self, forKey: .due)
        responsibleUID = try container.decodeIfPresent(String.self, forKey: .responsibleUID)
        dayOrder = try container.decodeIfPresent(Int.self, forKey: .dayOrder)
    }
}

/// A command's argument: text, a number or an object of them.
enum NotchTodoistValue: Codable, Equatable {
    case string(String)
    case int(Int)
    case object([String: NotchTodoistValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else {
            self = .object(try container.decode([String: NotchTodoistValue].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}

/// A change made here, waiting for Todoist. Kept on disk until Todoist has
/// answered it, so a change made offline or just before quitting is sent.
struct NotchTodoistCommand: Codable, Equatable {
    var type: String
    var uuid: String
    var tempID: String?
    var args: [String: NotchTodoistValue]

    private enum CodingKeys: String, CodingKey {
        case type, uuid, args
        case tempID = "temp_id"
    }

    var targetID: String? {
        if case .string(let id) = args["id"] { return id }
        return nil
    }

    /// The command once Todoist has given a temporary id its real one.
    func replacingID(_ old: String, with new: String) -> NotchTodoistCommand {
        guard targetID == old else { return self }
        var command = self
        command.args["id"] = .string(new)
        return command
    }
}

/// What a sync answered: the token for the next one, what changed, and how
/// each command sent with it went.
struct NotchTodoistResponse: Decodable {
    var syncToken: String
    var fullSync: Bool
    var items: [NotchTodoistItem]
    var userID: String?
    /// For each command, whether Todoist is done with it: applied, or
    /// refused for good. A command it could not apply for now is sent again.
    var finished: [String: Bool]
    var tempIDs: [String: String]

    private enum CodingKeys: String, CodingKey {
        case items, user
        case syncToken = "sync_token"
        case fullSync = "full_sync"
        case syncStatus = "sync_status"
        case tempIDMapping = "temp_id_mapping"
    }

    private struct User: Decodable {
        var id: String?

        private enum CodingKeys: String, CodingKey { case id }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = (try? container.decode(String.self, forKey: .id))
                ?? (try? container.decode(Int.self, forKey: .id)).map(String.init)
        }
    }

    private struct Status: Decodable {
        var finished: Bool

        private enum CodingKeys: String, CodingKey {
            case httpCode = "http_code"
        }

        init(from decoder: Decoder) throws {
            if (try? decoder.singleValueContainer().decode(String.self)) == "ok" {
                finished = true
                return
            }
            let code = try? decoder.container(keyedBy: CodingKeys.self).decode(Int.self, forKey: .httpCode)
            finished = code.map { $0 != 429 && $0 < 500 } ?? true
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        syncToken = try container.decode(String.self, forKey: .syncToken)
        fullSync = try container.decodeIfPresent(Bool.self, forKey: .fullSync) ?? false
        items = try container.decodeIfPresent([NotchTodoistItem].self, forKey: .items) ?? []
        userID = try container.decodeIfPresent(User.self, forKey: .user)?.id
        finished = try (container.decodeIfPresent([String: Status].self, forKey: .syncStatus) ?? [:]).mapValues(\.finished)
        tempIDs = try container.decodeIfPresent([String: String].self, forKey: .tempIDMapping) ?? [:]
    }
}

enum NotchTodoistSupport {
    static let endpoint = URL(string: "https://api.todoist.com/api/v1/sync")!
    /// Where Todoist shows the API token.
    static let tokenPage = URL(string: "https://app.todoist.com/app/settings/integrations/developer")!
    static let resourceTypes = #"["items","user"]"#
    static let fullSyncToken = "*"
    static let maximumCommands = 100
    static let queueFileName = "TodoistQueue.json"
    /// 1000 incremental syncs are allowed in 15 minutes; on screen the list
    /// asks 60 times in that while, and 15 times when it is not.
    static let pageInterval: TimeInterval = 15
    static let backgroundInterval: TimeInterval = 60
    static let maximumBackoff: TimeInterval = 5 * 60
    /// How long a reminder waits for Todoist before it goes out regardless.
    static let reminderWait: TimeInterval = 4

    /// "2026-10-16" for the day of `date`, as Todoist writes a day.
    static func dayString(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// The day a due date falls on here and its time of day, if it has one.
    static func occurrence(_ due: NotchTodoistDue, calendar: Calendar = .current) -> (day: String, minutes: Int?)? {
        let date = due.date
        guard date.count >= 10 else { return nil }
        if date.count == 10 { return (date, nil) }
        if date.hasSuffix("Z") {
            // The fraction is dropped: not every formatter reads six digits.
            let whole = date.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            guard let instant = formatter.date(from: whole) else { return nil }
            let parts = calendar.dateComponents([.hour, .minute], from: instant)
            return (dayString(instant, calendar: calendar), (parts.hour ?? 0) * 60 + (parts.minute ?? 0))
        }
        // A floating time is the same wall-clock time wherever the Mac is.
        let characters = Array(date)
        guard characters.count >= 16, characters[10] == "T",
              let hour = Int(String(characters[11...12])), let minute = Int(String(characters[14...15])),
              (0..<24).contains(hour), (0..<60).contains(minute) else { return nil }
        return (String(date.prefix(10)), hour * 60 + minute)
    }

    /// The due date a task added or moved here is given: floating, so it
    /// stays at that time of day.
    static func dueDate(day: String, minutes: Int?) -> String {
        guard let minutes else { return day }
        let clamped = NotchTaskSupport.clampedMinutes(minutes)
        return day + String(format: "T%02d:%02d:00", clamped / 60, clamped % 60)
    }

    /// Todoist's Markdown read as the list reads: a link is its words, and
    /// emphasis marks are dropped.
    static func plainText(_ content: String) -> String {
        content
            .replacingOccurrences(of: #"\[([^\]]*)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"(\*\*|__|~~|`)"#, with: "", options: .regularExpression)
    }

    /// The Today view's rule: tasks given to no one or to the user.
    static func isMine(_ item: NotchTodoistItem, userID: String?) -> Bool {
        guard let responsible = item.responsibleUID, !responsible.isEmpty else { return true }
        return userID.map { $0 == responsible } ?? true
    }

    /// Everything known after a sync: a full sync starts over, an
    /// incremental one changes what it names. A deleted task is remembered as
    /// deleted, so a row finished here is not kept for it.
    static func applying(_ response: NotchTodoistResponse, to items: [String: NotchTodoistItem]) -> [String: NotchTodoistItem] {
        var next = response.fullSync ? [:] : items
        for item in response.items { next[item.id] = item }
        return next
    }

    /// Whether a row is a Todoist task left from an earlier day, as Todoist's
    /// Today view lists it, apart and above the day's own.
    static func isOverdue(_ task: NotchTask, calendar: Calendar = .current) -> Bool {
        guard let link = task.todoist, let at = occurrence(link.due, calendar: calendar) else { return false }
        return at.day < link.day
    }

    /// When an overdue task was due, as its row reads it: "yesterday", or the
    /// date, with the year when it was another year.
    static func overdueLabel(_ link: NotchTodoistLink, locale: Locale, calendar: Calendar = .current) -> String? {
        guard let at = occurrence(link.due, calendar: calendar), let due = date(ofDay: at.day, calendar: calendar),
              let shown = date(ofDay: link.day, calendar: calendar), due < shown else { return nil }
        if calendar.dateComponents([.day], from: due, to: shown).day == 1 {
            let formatter = RelativeDateTimeFormatter()
            formatter.locale = locale
            formatter.calendar = calendar
            formatter.dateTimeStyle = .named
            return formatter.localizedString(from: DateComponents(day: -1))
        }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        let sameYear = calendar.component(.year, from: due) == calendar.component(.year, from: shown)
        formatter.setLocalizedDateFormatFromTemplate(sameYear ? "MMMd" : "yMMMd")
        return formatter.string(from: due)
    }

    /// Midnight starting a day written as Todoist writes it.
    static func date(ofDay day: String, calendar: Calendar = .current) -> Date? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    /// The list once Todoist has said what is due on `day`, and what is
    /// still open from before it. An overdue task has no time here. Tasks written
    /// here without Todoist are kept as they are; each row keeps its place
    /// and its identity, and new tasks follow in Todoist's order for the day.
    /// A task finished today stays struck through until midnight, though
    /// Todoist no longer lists it for today: a one-off task leaves the list
    /// once finished, and a repeating one moves to its next day.
    static func merged(_ current: [NotchTask], items: [String: NotchTodoistItem], userID: String?, day: String,
                       calendar: Calendar = .current) -> [NotchTask] {
        var fresh: [String: NotchTask] = [:]
        var order: [String] = []
        let sorted = items.values.sorted { ($0.dayOrder ?? .max, $0.id) < ($1.dayOrder ?? .max, $1.id) }
        for item in sorted {
            guard !item.isDeleted, isMine(item, userID: userID), let due = item.due,
                  let at = occurrence(due, calendar: calendar), at.day == day || (at.day < day && !item.checked),
                  let text = NotchTaskSupport.sanitizedText(plainText(item.content)) else { continue }
            fresh[item.id] = NotchTask(minutes: at.day == day ? at.minutes : nil, text: text, done: item.checked,
                                       todoist: NotchTodoistLink(id: item.id, day: day, due: due))
            order.append(item.id)
        }
        var result: [NotchTask] = []
        var placed = Set<String>()
        for task in current {
            guard let link = task.todoist else { result.append(task); continue }
            guard placed.insert(link.id).inserted else { continue }
            if var row = fresh[link.id] {
                row.id = task.id
                result.append(row)
            } else if link.day == day, items[link.id]?.isDeleted != true,
                      task.done || movedOn(link, item: items[link.id], day: day, calendar: calendar) {
                var row = task
                row.done = true
                result.append(row)
            }
        }
        for id in order where !placed.contains(id) {
            if let row = fresh[id] { result.append(row) }
        }
        return NotchTaskSupport.sanitized(result)
    }

    /// A repeating task now due after `day` was finished somewhere else.
    static func movedOn(_ link: NotchTodoistLink, item: NotchTodoistItem?, day: String, calendar: Calendar = .current) -> Bool {
        guard link.due.isRecurring, let due = item?.due, let next = occurrence(due, calendar: calendar) else { return false }
        return next.day > day
    }

    /// How long to wait after `failures` failed syncs in a row: doubling from
    /// the page's pace, never past five minutes, never before Todoist asks.
    static func backoff(failures: Int, retryAfter: TimeInterval?) -> TimeInterval {
        let doubled = pageInterval * pow(2, Double(max(0, failures - 1)))
        return max(retryAfter ?? 0, min(maximumBackoff, doubled))
    }

    // MARK: - Requests

    /// The form a sync is posted as: the token to read from and, when there
    /// are any, the changes made here.
    static func formBody(syncToken: String, commands: [NotchTodoistCommand]) -> Data? {
        var fields = [("sync_token", syncToken), ("resource_types", resourceTypes)]
        if !commands.isEmpty {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys
            guard let data = try? encoder.encode(commands), let json = String(data: data, encoding: .utf8) else { return nil }
            fields.append(("commands", json))
        }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        return fields.compactMap { key, value in
            value.addingPercentEncoding(withAllowedCharacters: allowed).map { "\(key)=\($0)" }
        }
        .joined(separator: "&").data(using: .utf8)
    }

    private static func command(_ type: String, _ args: [String: NotchTodoistValue], tempID: String? = nil) -> NotchTodoistCommand {
        NotchTodoistCommand(type: type, uuid: UUID().uuidString.lowercased(), tempID: tempID, args: args)
    }

    /// A task written here, due on `day`, and the link its row keeps until
    /// Todoist gives it an id.
    static func add(text: String, day: String, minutes: Int?) -> (command: NotchTodoistCommand, link: NotchTodoistLink) {
        let tempID = UUID().uuidString.lowercased()
        let due = NotchTodoistDue(date: dueDate(day: day, minutes: minutes))
        return (command("item_add", ["content": .string(text), "due": .object(["date": .string(due.date)])], tempID: tempID),
                NotchTodoistLink(id: tempID, day: day, due: due))
    }

    static func update(_ link: NotchTodoistLink, text: String) -> NotchTodoistCommand {
        command("item_update", ["id": .string(link.id), "content": .string(text)])
    }

    /// Due on the row's day at a time, or at none. A repeating task's time is
    /// left to Todoist, since a date alone would end its repeat.
    static func reschedule(_ link: NotchTodoistLink, minutes: Int?) -> NotchTodoistCommand? {
        guard !link.due.isRecurring else { return nil }
        return command("item_update", ["id": .string(link.id),
                                       "due": .object(["date": .string(dueDate(day: link.day, minutes: minutes))])])
    }

    /// Finishing closes the task as Todoist's own apps do: a one-off task is
    /// completed, a repeating one moves to its next day. Undoing reopens the
    /// one-off task, or brings the repeating one back to the day it left.
    static func toggle(_ link: NotchTodoistLink, done: Bool) -> NotchTodoistCommand {
        if done { return command("item_close", ["id": .string(link.id)]) }
        guard link.due.isRecurring else { return command("item_uncomplete", ["id": .string(link.id)]) }
        var due: [String: NotchTodoistValue] = ["date": .string(link.due.date)]
        if let string = link.due.string { due["string"] = .string(string) }
        if let timezone = link.due.timezone { due["timezone"] = .string(timezone) }
        return command("item_update_date_complete", ["id": .string(link.id), "due": .object(due), "is_forward": .int(0)])
    }

    static func delete(_ link: NotchTodoistLink) -> NotchTodoistCommand {
        command("item_delete", ["id": .string(link.id)])
    }

    /// The queue without a task Todoist has not yet heard of: its add and
    /// whatever was done to it since. Nil when the add has gone already.
    static func forgetting(_ tempID: String, in queue: [NotchTodoistCommand], sending: Set<String>) -> [NotchTodoistCommand]? {
        guard let add = queue.first(where: { $0.tempID == tempID }), !sending.contains(add.uuid) else { return nil }
        return queue.filter { $0.tempID != tempID && $0.targetID != tempID }
    }
}

/// The changes waiting for Todoist, on disk beside the list.
struct NotchTodoistQueueStore {
    let directoryURL: URL?

    func load() -> [NotchTodoistCommand] {
        guard let directoryURL,
              let data = try? Data(contentsOf: directoryURL.appendingPathComponent(NotchTodoistSupport.queueFileName)) else { return [] }
        return (try? JSONDecoder().decode([NotchTodoistCommand].self, from: data)) ?? []
    }

    @discardableResult
    func save(_ queue: [NotchTodoistCommand]) -> Bool {
        guard let directoryURL, let data = try? JSONEncoder().encode(queue) else { return false }
        return PrivateFileStore.createDirectory(at: directoryURL)
            && PrivateFileStore.write(data, to: directoryURL.appendingPathComponent(NotchTodoistSupport.queueFileName))
    }
}
