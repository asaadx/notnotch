// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// A short to-do list in the island, one line a task: "5pm — gym". Clicking
/// the words strikes them through and leaves the row where it is; clicking
/// the time turns up the Clock's drums for it. New tasks are written on the
/// last line.
struct NotchTasksView: View {
    @ObservedObject var service: NotchService
    @ObservedObject private var tasks = NotchTaskService.shared
    @ObservedObject private var l10n = L10n.shared
    @State private var draftText = ""
    @State private var draftMinutes = NotchTaskSupport.suggestedMinutes(now: Date())
    @State private var editingID: UUID?
    @State private var editingText = ""
    @State private var picking: Picking?
    @State private var hoveredID: UUID?
    @FocusState private var focus: Field?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var text: NotchTaskStrings { FeatureStrings.notchTasks(l10n.language) }
    private static let rowHeight: CGFloat = 28

    private enum Field: Hashable {
        case draft
        case edit(UUID)
    }

    /// Whose time the drums are setting: a row, or the line being written.
    private struct Picking: Equatable {
        let id: UUID?
        var time: NotchTaskTime
    }

    var body: some View {
        Group {
            if tasks.loadFailed {
                NotchEmptyView(symbol: "exclamationmark.triangle", message: text.loadFailed)
            } else if let picking {
                picker(picking)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            } else {
                list.transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(reduceMotion ? nil : .smooth(duration: 0.22), value: picking == nil)
        .onAppear { tasks.load() }
    }

    // MARK: - List

    private var list: some View {
        VStack(spacing: 6) {
            if tasks.tasks.isEmpty {
                NotchEmptyView(symbol: "checklist", message: text.empty)
            } else {
                ScrollView(.vertical) {
                    VStack(spacing: 2) {
                        ForEach(tasks.tasks) { row($0) }
                    }
                }
                .scrollIndicators(.never)
            }
            if tasks.saveFailed {
                Label(text.saveFailed, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.6))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            composer
        }
    }

    private func row(_ task: NotchTask) -> some View {
        let editing = editingID == task.id
        let showsActions = !editing && hoveredID == task.id
        return HStack(spacing: 6) {
            timeButton(task.minutes, done: task.done) {
                picking = Picking(id: task.id, time: NotchTaskTime(minutes: task.minutes))
            }
            dash(done: task.done)
            if editing {
                TextField(text.placeholder, text: $editingText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .focused($focus, equals: .edit(task.id))
                    .onSubmit { finishEditing(task.id) }
                    .onExitCommand { editingID = nil }
            } else {
                Button { toggle(task.id) } label: {
                    NotchStruckText(text: NotchTaskSupport.displayText(task.text), done: task.done,
                                    reduceMotion: reduceMotion)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(NotchTaskSupport.rowText(task))
                .accessibilityHint(task.done ? text.markNotDone : text.markDone)
                .accessibilityAddTraits(task.done ? .isSelected : [])
            }
            if showsActions {
                rowAction("pencil", title: text.edit) { beginEditing(task) }
                rowAction("trash", title: text.delete) { delete(task.id) }
            }
        }
        .padding(.horizontal, 8)
        .frame(height: Self.rowHeight)
        .background(.white.opacity(hoveredID == task.id || editing ? 0.06 : 0),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onHover { hovering in
            if hovering { hoveredID = task.id } else if hoveredID == task.id { hoveredID = nil }
        }
        .contextMenu {
            Button(text.edit) { beginEditing(task) }
            Button(task.done ? text.markNotDone : text.markDone) { toggle(task.id) }
            Divider()
            Button(text.delete, role: .destructive) { delete(task.id) }
        }
    }

    /// The line a new task is written on, with the time it will take.
    private var composer: some View {
        HStack(spacing: 6) {
            timeButton(draftMinutes, done: false) {
                picking = Picking(id: nil, time: NotchTaskTime(minutes: draftMinutes))
            }
            dash(done: false)
            TextField(tasks.canAdd ? text.placeholder : String(format: text.limitFormat, NotchTaskSupport.maximumCount),
                      text: $draftText)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .focused($focus, equals: .draft)
                .disabled(!tasks.canAdd)
                .onSubmit(add)
                .accessibilityLabel(text.newTask)
            NotchIconButton(symbol: "plus", title: text.add, action: add)
                .disabled(!tasks.canAdd || NotchTaskSupport.sanitizedText(draftText) == nil)
        }
        .padding(.leading, 8)
        .frame(height: 32)
        .modifier(NotchControlSurface(cornerRadius: 10, interactive: false))
    }

    private func timeButton(_ minutes: Int, done: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(NotchTaskSupport.timeLabel(minutes))
                .font(.system(size: 14, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(done ? 0.3 : 0.6))
                .fixedSize()
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(text.time)
        .accessibilityLabel(text.time)
        .accessibilityValue(NotchTaskSupport.timeLabel(minutes))
    }

    private func dash(done: Bool) -> some View {
        Text("—")
            .font(.system(size: 14))
            .foregroundStyle(.white.opacity(done ? 0.25 : 0.4))
            .accessibilityHidden(true)
    }

    private func rowAction(_ symbol: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(NotchButtonStyle(cornerRadius: 7, lifts: false))
        .help(title)
        .accessibilityLabel(title)
    }

    // MARK: - Time

    private func picker(_ current: Picking) -> some View {
        VStack(spacing: 8) {
            NotchTaskTimePicker(time: Binding(get: { picking?.time ?? current.time },
                                              set: { picking?.time = $0 }),
                                text: text)
                .frame(maxWidth: .infinity, maxHeight: 170)
            HStack {
                NotchPillButton(title: text.cancel) { picking = nil }
                Spacer(minLength: 0)
                Button(action: commitTime) {
                    Text(text.save)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 14)
                        .frame(height: 28)
                        .background(.orange.opacity(0.18), in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(NotchButtonStyle(cornerRadius: 14))
                .keyboardShortcut(.defaultAction)
            }
        }
        .frame(maxWidth: 300)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onExitCommand { picking = nil }
    }

    private func commitTime() {
        guard let picking else { return }
        if let id = picking.id {
            tasks.update(id, minutes: picking.time.minutes)
        } else {
            draftMinutes = picking.time.minutes
            focus = .draft
        }
        self.picking = nil
    }

    // MARK: - Actions

    private func add() {
        guard tasks.add(minutes: draftMinutes, text: draftText) else { return }
        draftText = ""
        focus = .draft
    }

    private func toggle(_ id: UUID) {
        // Only the line moves; the row keeps its place in the list.
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.28)) { tasks.toggle(id) }
    }

    private func beginEditing(_ task: NotchTask) {
        editingText = task.text
        editingID = task.id
        focus = .edit(task.id)
    }

    private func finishEditing(_ id: UUID) {
        tasks.update(id, text: editingText)
        editingID = nil
    }

    private func delete(_ id: UUID) {
        if editingID == id { editingID = nil }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { tasks.delete(id) }
    }
}

/// A task's words with a line drawn across them from the leading edge as it
/// is done, and drawn back as it is undone.
private struct NotchStruckText: View {
    let text: String
    let done: Bool
    let reduceMotion: Bool

    var body: some View {
        Text(text)
            .font(.system(size: 14))
            .lineLimit(1)
            .foregroundStyle(.white.opacity(done ? 0.4 : 0.92))
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.7))
                    .frame(height: 1.5)
                    .scaleEffect(x: done ? 1 : 0, anchor: .leading)
                    .opacity(done || !reduceMotion ? 1 : 0)
            }
            .fixedSize(horizontal: false, vertical: true)
    }
}
