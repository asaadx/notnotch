// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The island's to-do list, read by time of day. Finishing a task strikes it
/// through in place; only a new time moves it. At a task's time the island
/// says so, or macOS does when the island cannot, and while the app is not
/// running. With Todoist connected the list is also today's tasks there,
/// and what is done here is sent back.
final class NotchTaskService: ObservableObject {
    static let shared = NotchTaskService()

    @Published private(set) var tasks: [NotchTask] = []
    @Published private(set) var loadFailed = false
    @Published private(set) var saveFailed = false
    /// A time being picked, a row being edited or a task being written. The
    /// island stays open around it, as it does for the tools being edited.
    @Published var interacting = false
    /// The time the next task is written at, kept while the island closes.
    var draftMinutes: Int?
    private var store = NotchTaskStore(directoryURL: PrivateFileStore.containerURL)
    private var loaded = false
    private var reminderTimer: DispatchSourceTimer?
    private var lastReminderCheck = Date()

    var canAdd: Bool { tasks.count < NotchTaskSupport.maximumCount }

    /// Reads the list once; a failed read is tried again on the next visit.
    /// Todoist's rows for another day are left behind.
    func load() {
        guard !loaded else { return }
        do {
            let today = NotchTodoistSupport.dayString(Date())
            tasks = try store.load().filter { $0.todoist.map { $0.day == today } ?? true }
            loaded = true
            loadFailed = false
        } catch {
            loadFailed = true
        }
    }

    @discardableResult
    func add(minutes: Int, text: String) -> Bool {
        guard canAdd, let text = NotchTaskSupport.sanitizedText(text) else { return false }
        var task = NotchTask(minutes: NotchTaskSupport.clampedMinutes(minutes), text: text)
        let todoist = NotchTodoistService.shared
        // With Todoist connected, a new task is due there today.
        let added = todoist.connected
            ? NotchTodoistSupport.add(text: text, day: NotchTodoistSupport.dayString(Date()), minutes: task.minutes) : nil
        task.todoist = added?.link
        commit(tasks + [task])
        todoist.enqueue(added?.command)
        draftMinutes = NotchTaskSupport.followingMinutes(after: tasks)
        // Asked once, with the first task that could need it.
        if NotchSupport.routes(.tasks) { Notifier.requestPermission() }
        return true
    }

    /// A repeating Todoist task keeps the time Todoist gives it.
    func canRetime(_ task: NotchTask) -> Bool {
        task.todoist?.due.isRecurring != true
    }

    func update(_ id: UUID, text: String) {
        guard let index = tasks.firstIndex(where: { $0.id == id }),
              let text = NotchTaskSupport.sanitizedText(text), text != tasks[index].text else { return }
        var next = tasks
        next[index].text = text
        commit(next)
        if let link = next[index].todoist { NotchTodoistService.shared.enqueue(NotchTodoistSupport.update(link, text: text)) }
    }

    /// A new time moves a task to the kill list, and none to whenever. A
    /// Todoist task is due today at it, an overdue one included.
    func setTime(_ id: UUID, minutes: Int?) {
        guard let index = tasks.firstIndex(where: { $0.id == id }), canRetime(tasks[index]) else { return }
        let minutes = minutes.map(NotchTaskSupport.clampedMinutes)
        var next = tasks
        next[index].minutes = minutes
        if let day = next[index].todoist?.day {
            next[index].todoist?.due = NotchTodoistDue(date: NotchTodoistSupport.dueDate(day: day, minutes: minutes))
        }
        guard next != tasks else { return }
        commit(next)
        if let link = next[index].todoist {
            NotchTodoistService.shared.enqueue(NotchTodoistSupport.reschedule(link, minutes: minutes))
        }
    }

    func toggle(_ id: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        var next = tasks
        next[index].done.toggle()
        commit(next)
        if let link = next[index].todoist {
            NotchTodoistService.shared.enqueue(NotchTodoistSupport.toggle(link, done: next[index].done))
        }
    }

    func delete(_ id: UUID) {
        let link = tasks.first { $0.id == id }?.todoist
        commit(tasks.filter { $0.id != id })
        if let link { NotchTodoistService.shared.delete(link) }
    }

    // MARK: - Todoist

    /// The list as Todoist last described today.
    func applyTodoist(_ items: [String: NotchTodoistItem], userID: String?) {
        load()
        commit(NotchTodoistSupport.merged(tasks, items: items, userID: userID, day: NotchTodoistSupport.dayString(Date())),
               byUser: false)
    }

    /// A task added here, once Todoist has given it its id.
    func replaceTodoistID(_ temporary: String, with real: String) {
        guard let index = tasks.firstIndex(where: { $0.todoist?.id == temporary }) else { return }
        var next = tasks
        next[index].todoist?.id = real
        commit(next, byUser: false)
    }

    /// Todoist disconnected: its rows go, tasks written without it stay.
    func dropTodoist() {
        load()
        commit(tasks.filter { $0.todoist == nil }, byUser: false)
    }

    private func commit(_ next: [NotchTask], byUser: Bool = true) {
        guard loaded, next != tasks else { return }
        tasks = next
        saveFailed = !store.save(next)
        // A task added or moved into the past is not overdue news. A sync
        // leaves the window alone, so a reminder it lands beside still comes.
        if byUser { lastReminderCheck = Date() }
        scheduleReminder()
    }

    // MARK: - Reminders

    /// Runs while the island routes task reminders. Reminders macOS was
    /// holding for while the app was closed are taken back.
    func syncReminders() {
        Notifier.removePending(withPrefix: NotchTaskSupport.reminderPrefix)
        guard NotchSupport.routes(.tasks) else { stopReminders(); return }
        load()
        if reminderTimer == nil { lastReminderCheck = Date() }
        scheduleReminder(force: true)
    }

    func stopReminders() {
        reminderTimer?.cancel()
        reminderTimer = nil
    }

    /// On quit, macOS takes over each task's next reminder.
    func handOffReminders() {
        guard reminderTimer != nil else { return }
        stopReminders()
        let title = FeatureStrings.notchTasks(L10n.shared.language).title
        Notifier.schedule(NotchTaskSupport.handedOff(tasks, after: Date()).compactMap { task in
            task.minutes.map { minutes in
                (identifier: NotchTaskSupport.reminderPrefix + task.id.uuidString, title: title,
                 body: NotchTaskSupport.rowText(task), hour: minutes / 60, minute: minutes % 60)
            }
        }, timeout: 1)
    }

    /// A wall-clock deadline, so time asleep still counts toward it.
    private func scheduleReminder(force: Bool = false) {
        guard force || reminderTimer != nil else { return }
        stopReminders()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        let next = NotchTaskSupport.nextReminder(tasks, after: Date())
        // With nothing to remind, it still wakes daily to keep running.
        let delay = next.map { max(0, $0.timeIntervalSinceNow) + 0.5 } ?? 24 * 60 * 60
        timer.schedule(wallDeadline: .now() + delay, leeway: .seconds(1))
        timer.setEventHandler { [weak self] in self?.remindDue() }
        timer.resume()
        reminderTimer = timer
    }

    /// Todoist is asked first, so a task finished on the phone stays quiet.
    private func remindDue() {
        let from = max(lastReminderCheck, Date().addingTimeInterval(-NotchTaskSupport.reminderGrace))
        NotchTodoistService.shared.refresh { [weak self] in
            guard let self else { return }
            let now = Date()
            lastReminderCheck = now
            NotchTaskSupport.dueTasks(tasks, from: from, to: now).forEach(remind)
            scheduleReminder()
        }
    }

    /// The island tells it like the list reads; a page already showing the
    /// list needs no notice.
    private func remind(_ task: NotchTask) {
        let notch = NotchService.shared
        let onPage = notch.expanded && notch.selected == .tasks
        let shown = onPage || notch.show(NotchNotice(event: .tasks, title: NotchTaskSupport.timeLabel(task.minutes ?? 0),
                                                     detail: NotchTaskSupport.displayText(task.text),
                                                     symbol: NotchModule.tasks.symbol))
        if !shown {
            Notifier.post(title: FeatureStrings.notchTasks(L10n.shared.language).title, body: NotchTaskSupport.rowText(task))
        }
    }
}
