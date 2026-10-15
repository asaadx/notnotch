// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The island's to-do list, read by time of day. Finishing a task strikes it
/// through in place; only a new time moves it. At a task's time the island
/// says so, or macOS does when the island cannot, and while the app is not
/// running.
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
    func load() {
        guard !loaded else { return }
        do {
            tasks = try store.load()
            loaded = true
            loadFailed = false
        } catch {
            loadFailed = true
        }
    }

    @discardableResult
    func add(minutes: Int, text: String) -> Bool {
        guard canAdd, let text = NotchTaskSupport.sanitizedText(text) else { return false }
        commit(tasks + [NotchTask(minutes: NotchTaskSupport.clampedMinutes(minutes), text: text)])
        draftMinutes = NotchTaskSupport.followingMinutes(after: minutes)
        // Asked once, with the first task that could need it.
        if NotchSupport.routes(.tasks) { Notifier.requestPermission() }
        return true
    }

    func update(_ id: UUID, minutes: Int? = nil, text: String? = nil) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        var next = tasks
        if let minutes { next[index].minutes = NotchTaskSupport.clampedMinutes(minutes) }
        if let text {
            guard let text = NotchTaskSupport.sanitizedText(text) else { return }
            next[index].text = text
        }
        commit(next)
    }

    func toggle(_ id: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        var next = tasks
        next[index].done.toggle()
        commit(next)
    }

    func delete(_ id: UUID) {
        commit(tasks.filter { $0.id != id })
    }

    private func commit(_ next: [NotchTask]) {
        guard loaded, next != tasks else { return }
        tasks = next
        saveFailed = !store.save(next)
        // A task added or moved into the past is not overdue news.
        lastReminderCheck = Date()
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
        Notifier.schedule(tasks.filter { !$0.done }.map { task in
            (identifier: NotchTaskSupport.reminderPrefix + task.id.uuidString, title: title,
             body: NotchTaskSupport.rowText(task), hour: task.minutes / 60, minute: task.minutes % 60)
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

    private func remindDue() {
        let now = Date()
        let from = max(lastReminderCheck, now.addingTimeInterval(-NotchTaskSupport.reminderGrace))
        lastReminderCheck = now
        NotchTaskSupport.dueTasks(tasks, from: from, to: now).forEach(remind)
        scheduleReminder()
    }

    /// The island tells it like the list reads; a page already showing the
    /// list needs no notice.
    private func remind(_ task: NotchTask) {
        let notch = NotchService.shared
        let onPage = notch.expanded && notch.selected == .tasks
        let shown = onPage || notch.show(NotchNotice(event: .tasks, title: NotchTaskSupport.timeLabel(task.minutes),
                                                     detail: NotchTaskSupport.displayText(task.text),
                                                     symbol: NotchModule.tasks.symbol))
        if !shown {
            Notifier.post(title: FeatureStrings.notchTasks(L10n.shared.language).title, body: NotchTaskSupport.rowText(task))
        }
    }
}
