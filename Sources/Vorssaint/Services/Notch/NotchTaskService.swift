// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The island's to-do list. Rows stay where they were added: finishing one
/// strikes it through in place and changing its time never moves it.
@MainActor
final class NotchTaskService: ObservableObject {
    static let shared = NotchTaskService()

    @Published private(set) var tasks: [NotchTask] = []
    @Published private(set) var loadFailed = false
    @Published private(set) var saveFailed = false
    private var store = NotchTaskStore(directoryURL: PrivateFileStore.containerURL)
    private var loaded = false

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
    }
}
