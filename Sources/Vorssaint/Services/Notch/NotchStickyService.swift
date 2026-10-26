// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The island's sticky notes. A new note comes in the next colour; a note
/// left blank goes when it is put away. Typing is saved a moment after it
/// pauses, and at once when the note is put away.
final class NotchStickyService: ObservableObject {
    static let shared = NotchStickyService()

    /// Oldest first.
    @Published private(set) var notes: [NotchSticky] = []
    @Published private(set) var loadFailed = false
    @Published private(set) var saveFailed = false
    /// A note is open for writing. The island stays open around it.
    @Published var editing = false
    private var store = NotchStickyStore(directoryURL: PrivateFileStore.containerURL)
    private var loaded = false
    private var pendingSave: DispatchWorkItem?

    var canAdd: Bool { notes.count < NotchStickySupport.maximumCount }

    /// Reads the notes once; a failed read is tried again on the next visit.
    func load() {
        guard !loaded else { return }
        do {
            notes = try store.load()
            loaded = true
            loadFailed = false
        } catch {
            loadFailed = true
        }
    }

    /// A blank note, for writing on at once.
    func add() -> UUID? {
        guard loaded, canAdd else { return nil }
        let note = NotchSticky(color: NotchStickySupport.nextColor(after: notes))
        notes.append(note)
        save()
        return note.id
    }

    func update(_ id: UUID, text: String) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        let text = String(text.prefix(NotchStickySupport.maximumTextLength))
        guard text != notes[index].text else { return }
        notes[index].text = text
        saveSoon()
    }

    func setColor(_ id: UUID, _ color: NotchStickyColor) {
        guard let index = notes.firstIndex(where: { $0.id == id }), notes[index].color != color else { return }
        notes[index].color = color
        save()
    }

    func delete(_ id: UUID) {
        guard notes.contains(where: { $0.id == id }) else { return }
        notes.removeAll { $0.id == id }
        save()
    }

    /// The note put away: its trailing space trimmed, or gone if nothing
    /// was written on it.
    func finish(_ id: UUID) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        if NotchStickySupport.isBlank(notes[index]) {
            notes.remove(at: index)
        } else {
            notes[index].text = NotchStickySupport.sanitizedText(notes[index].text)
        }
        save()
    }

    /// Typing not yet written goes to disk, as the app quits.
    func flush() {
        if pendingSave != nil { save() }
    }

    private func saveSoon() {
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.save() }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + NotchStickySupport.saveDelay, execute: work)
    }

    private func save() {
        pendingSave?.cancel()
        pendingSave = nil
        guard loaded else { return }
        saveFailed = !store.save(notes)
    }
}
