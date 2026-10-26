// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Todoist's due dates read on the Mac's day, the list rebuilt from what a
/// sync says, the commands sent back and the form they are posted in.
enum NotchTodoistTests {
    static func run(_ suite: TestSuite) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        func occurrence(_ date: String) -> (day: String, minutes: Int?)? {
            NotchTodoistSupport.occurrence(NotchTodoistDue(date: date), calendar: calendar)
        }
        suite.expect(occurrence("2026-10-16").map { $0.day == "2026-10-16" && $0.minutes == nil } == true,
                     "a full-day date has no time")
        suite.expect(occurrence("2026-10-16T17:30:00.000000").map { $0.day == "2026-10-16" && $0.minutes == 17 * 60 + 30 } == true,
                     "a floating time is read as written")
        suite.expect(occurrence("2026-10-16T21:00:00.000000Z").map { $0.day == "2026-10-16" && $0.minutes == 17 * 60 } == true,
                     "a fixed time in UTC is read on the Mac's clock")
        suite.expect(occurrence("2026-10-17T02:00:00Z").map { $0.day == "2026-10-16" && $0.minutes == 22 * 60 } == true,
                     "a fixed time can fall on the day before in UTC terms")
        suite.expect(occurrence("garbage") == nil && occurrence("2026-10-16T9") == nil, "an unreadable date is skipped")
        suite.expect(NotchTodoistSupport.dueDate(day: "2026-10-16", minutes: 9 * 60 + 5) == "2026-10-16T09:05:00"
                        && NotchTodoistSupport.dueDate(day: "2026-10-16", minutes: nil) == "2026-10-16",
                     "a due date written here is floating, or a day alone")
        suite.expect(NotchTodoistSupport.plainText("Read [the doc](https://x.y) **now**") == "Read the doc now",
                     "Markdown reads as plain words")

        let day = "2026-10-16"
        let local = NotchTask(minutes: 8 * 60, text: "stretch")
        let items: [String: NotchTodoistItem] = [
            "a": NotchTodoistItem(id: "a", content: "Gym", due: NotchTodoistDue(date: "2026-10-16T17:00:00"), dayOrder: 2),
            "b": NotchTodoistItem(id: "b", content: "Groceries", due: NotchTodoistDue(date: day), dayOrder: 1),
            "c": NotchTodoistItem(id: "c", content: "Tomorrow", due: NotchTodoistDue(date: "2026-10-17")),
            "d": NotchTodoistItem(id: "d", content: "Not mine", due: NotchTodoistDue(date: day), responsibleUID: "other"),
            "e": NotchTodoistItem(id: "e", content: "No date"),
            "f": NotchTodoistItem(id: "f", content: "Gone", isDeleted: true, due: NotchTodoistDue(date: day)),
        ]
        let first = NotchTodoistSupport.merged([local], items: items, userID: "me", day: day, calendar: calendar)
        suite.expect(first.map(\.text) == ["stretch", "Groceries", "Gym"],
                     "today's tasks follow the list's own, in Todoist's order; others' and other days' are left out")
        suite.expect(first.first { $0.text == "Groceries" }?.minutes == nil, "a task due today with no time reads under Anytime")
        suite.expect(NotchTaskSupport.anytime(first).map(\.text) == ["Groceries"]
                        && NotchTaskSupport.ordered(first).map(\.text) == ["stretch", "Gym"],
                     "timed rows and Anytime rows are read apart")

        guard let gym = first.first(where: { $0.todoist?.id == "a" }) else {
            suite.expect(false, "the timed Todoist task is in the list")
            return
        }
        var renamed = items
        renamed["a"]?.content = "Gym class"
        let second = NotchTodoistSupport.merged(first, items: renamed, userID: "me", day: day, calendar: calendar)
        suite.expect(second.first { $0.todoist?.id == "a" }.map { $0.id == gym.id && $0.text == "Gym class" } == true,
                     "a row changed in Todoist keeps its identity and place")

        // Finished here: a one-off task is checked, then a full sync drops it.
        var finished = first
        if let index = finished.firstIndex(where: { $0.todoist?.id == "b" }) { finished[index].done = true }
        var checked = items
        checked["b"]?.checked = true
        let struck = NotchTodoistSupport.merged(finished, items: checked, userID: "me", day: day, calendar: calendar)
        suite.expect(struck.first { $0.todoist?.id == "b" }?.done == true, "a checked task is struck through")
        var archived = items
        archived["b"] = nil
        let kept = NotchTodoistSupport.merged(struck, items: archived, userID: "me", day: day, calendar: calendar)
        suite.expect(kept.first { $0.todoist?.id == "b" }?.done == true, "a task finished today stays until midnight")
        let tomorrow = NotchTodoistSupport.merged(kept, items: archived, userID: "me", day: "2026-10-17", calendar: calendar)
        suite.expect(!tomorrow.contains { $0.todoist?.id == "b" } && tomorrow.contains { $0.todoist?.id == "c" }
                        && tomorrow.contains { $0.text == "stretch" },
                     "at midnight yesterday's rows go, today's come in and the list's own stay")

        // Finished on the phone: a repeating task moves to its next day.
        let repeating = NotchTodoistDue(date: "2026-10-16T09:00:00", string: "every day at 9", isRecurring: true)
        let daily = ["r": NotchTodoistItem(id: "r", content: "Meds", due: repeating)]
        let shown = NotchTodoistSupport.merged([], items: daily, userID: nil, day: day, calendar: calendar)
        var moved = daily
        moved["r"]?.due?.date = "2026-10-17T09:00:00"
        let afterPhone = NotchTodoistSupport.merged(shown, items: moved, userID: nil, day: day, calendar: calendar)
        suite.expect(afterPhone.first { $0.todoist?.id == "r" }?.done == true,
                     "a repeating task finished elsewhere is struck through for the rest of the day")
        var rescheduled = items
        rescheduled["a"]?.due = NotchTodoistDue(date: "2026-10-18T17:00:00")
        suite.expect(!NotchTodoistSupport.merged(first, items: rescheduled, userID: "me", day: day, calendar: calendar)
                        .contains { $0.todoist?.id == "a" },
                     "a one-off task moved to another day leaves the list")
        var deleted = items
        deleted["b"]?.isDeleted = true
        suite.expect(!NotchTodoistSupport.merged(struck, items: deleted, userID: "me", day: day, calendar: calendar)
                        .contains { $0.todoist?.id == "b" },
                     "a finished task deleted in Todoist leaves the list")

        // Commands.
        let added = NotchTodoistSupport.add(text: "call mom", day: day, minutes: 18 * 60)
        suite.expect(added.command.type == "item_add" && added.command.tempID == added.link.id
                        && added.command.args["due"] == .object(["date": .string("2026-10-16T18:00:00")]),
                     "a task added here is due today at its time, under a temporary id")
        suite.expect(NotchTodoistSupport.reschedule(shown[0].todoist!, minutes: 10 * 60) == nil,
                     "a repeating task's time is not overwritten")
        let overdueLink = NotchTodoistLink(id: "o", day: day, due: NotchTodoistDue(date: "2026-09-10"))
        suite.expect(NotchTodoistSupport.reschedule(overdueLink, minutes: 9 * 60)?.args["due"]
                        == .object(["date": .string("2026-10-16T09:00:00")])
                        && NotchTodoistSupport.reschedule(gym.todoist!, minutes: nil)?.args["due"]
                        == .object(["date": .string(day)]),
                     "a time given here makes a task due today at it; none leaves it due today")
        suite.expect(NotchTodoistSupport.toggle(gym.todoist!, done: true).type == "item_close"
                        && NotchTodoistSupport.toggle(gym.todoist!, done: false).type == "item_uncomplete",
                     "a one-off task is closed and reopened")
        let undo = NotchTodoistSupport.toggle(shown[0].todoist!, done: false)
        suite.expect(undo.type == "item_update_date_complete" && undo.args["is_forward"] == .int(0)
                        && undo.args["due"] == .object(["date": .string("2026-10-16T09:00:00"), "string": .string("every day at 9")]),
                     "undoing a repeating task brings it back to today")
        let edit: NotchTodoistCommand? = NotchTodoistSupport.update(gym.todoist!, text: "lift")
        let queue = [added.command, edit!, NotchTodoistCommand(type: "item_close", uuid: "x", args: ["id": .string(added.link.id)])]
        suite.expect(NotchTodoistSupport.forgetting(added.link.id, in: queue, sending: [])?.map(\.uuid) == [edit!.uuid],
                     "a task deleted before Todoist heard of it is never sent")
        suite.expect(NotchTodoistSupport.forgetting(added.link.id, in: queue, sending: [added.command.uuid]) == nil,
                     "one already on its way is deleted in Todoist instead")
        suite.expect(queue[2].replacingID(added.link.id, with: "real").targetID == "real",
                     "a temporary id is replaced once Todoist gives the real one")

        let form = NotchTodoistSupport.formBody(syncToken: "*", commands: [added.command])
            .flatMap { String(data: $0, encoding: .utf8) } ?? ""
        suite.expect(form.hasPrefix("sync_token=%2A&resource_types=%5B%22items%22%2C%22user%22%5D&commands=%5B%7B"),
                     "the sync is posted as a form, its JSON percent-encoded")
        suite.expect(!form.contains("+") && !form.contains(" "), "nothing in the form is left unescaped")

        let reply = Data(#"""
        {"sync_token":"next","full_sync":false,"user":{"id":"42"},
         "items":[{"id":"a","content":"Gym","checked":true,"is_deleted":false,
                   "due":{"date":"2026-10-16T17:00:00","timezone":null,"string":"today at 5pm","lang":"en","is_recurring":false}}],
         "sync_status":{"ok-cmd":"ok","bad-cmd":{"error_code":20,"error":"Invalid argument value","http_code":400},
                        "busy-cmd":{"error_code":42,"error":"Too many requests","http_code":429}},
         "temp_id_mapping":{"tmp":"real"}}
        """#.utf8)
        let response = try? JSONDecoder().decode(NotchTodoistResponse.self, from: reply)
        suite.expect(response?.syncToken == "next" && response?.userID == "42" && response?.items.first?.checked == true
                        && response?.tempIDs == ["tmp": "real"],
                     "a sync's answer is read")
        suite.expect(response?.finished == ["ok-cmd": true, "bad-cmd": true, "busy-cmd": false],
                     "an applied or refused command is done with; a throttled one is sent again")
        let merged = response.map { NotchTodoistSupport.applying($0, to: ["z": NotchTodoistItem(id: "z", content: "kept")]) }
        suite.expect(merged?.keys.sorted() == ["a", "z"], "an incremental sync changes only what it names")

        suite.expect(NotchTodoistSupport.backoff(failures: 1, retryAfter: nil) == 15
                        && NotchTodoistSupport.backoff(failures: 3, retryAfter: nil) == 60
                        && NotchTodoistSupport.backoff(failures: 10, retryAfter: nil) == 300
                        && NotchTodoistSupport.backoff(failures: 1, retryAfter: 90) == 90,
                     "failed syncs back off, but never sooner than Todoist asks")

        let link = NotchTodoistLink(id: "a", day: day, due: NotchTodoistDue(date: day))
        let stored = [NotchTask(minutes: nil, text: "anytime", todoist: link), NotchTask(minutes: 600, text: "old")]
        let decoded = (try? JSONEncoder().encode(stored)).flatMap { try? JSONDecoder().decode([NotchTask].self, from: $0) }
        suite.expect(decoded == stored, "a row with no time and its Todoist link survive a restart")
        let legacy = Data(#"[{"id":"7C9E6679-7425-40DE-944B-E07FC1F90AE7","minutes":600,"text":"gym","done":false}]"#.utf8)
        suite.expect((try? JSONDecoder().decode([NotchTask].self, from: legacy))?.first?.minutes == 600,
                     "a list saved before Todoist still reads")

        let late = ["o": NotchTodoistItem(id: "o", content: "Cold emails", due: NotchTodoistDue(date: "2026-09-10")),
                    "y": NotchTodoistItem(id: "y", content: "Grooming", due: NotchTodoistDue(date: "2026-10-15T09:00:00")),
                    "x": NotchTodoistItem(id: "x", content: "Done before", checked: true, due: NotchTodoistDue(date: "2026-10-15"))]
        let behind = NotchTodoistSupport.merged([], items: late, userID: nil, day: day, calendar: calendar)
        suite.expect(NotchTaskSupport.overdue(behind).map(\.text).sorted() == ["Cold emails", "Grooming"]
                        && behind.allSatisfy { $0.minutes == nil } && NotchTaskSupport.anytime(behind).isEmpty,
                     "open tasks from earlier days read as overdue, with no time; finished ones are left out")

        let english = Locale(identifier: "en_US")
        suite.expect(NotchTodoistSupport.overdueLabel(behind.first { $0.text == "Grooming" }!.todoist!, locale: english,
                                                      calendar: calendar) == "yesterday"
                        && NotchTodoistSupport.overdueLabel(behind.first { $0.text == "Cold emails" }!.todoist!, locale: english,
                                                            calendar: calendar) == "Sep 10",
                     "an overdue task reads the day it was due: yesterday, or its date")

        let at = { (hour: Int) in calendar.date(from: DateComponents(year: 2026, month: 10, day: 16, hour: hour))! }
        let remindable = [NotchTask(minutes: 9 * 60, text: "local"),
                          NotchTask(minutes: 9 * 60, text: "todoist", todoist: link),
                          NotchTask(minutes: 20 * 60, text: "later", todoist: link),
                          NotchTask(minutes: nil, text: "anytime", todoist: link)]
        suite.expect(NotchTaskSupport.handedOff(remindable, after: at(12), calendar: calendar).map(\.text) == ["local", "later"],
                     "macOS is not handed a Todoist reminder whose time today has passed, nor one with no time")
        suite.expect(NotchTaskSupport.nextReminder(Array(remindable.dropFirst()), after: at(21), calendar: calendar) == nil,
                     "a Todoist task is not reminded of tomorrow")
    }
}
