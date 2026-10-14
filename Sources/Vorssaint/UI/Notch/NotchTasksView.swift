// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// A short to-do list in the island, one line a task: "5pm — gym", read by
/// time of day. Clicking the words strikes them through and leaves the row
/// where it is; clicking the time turns up the Clock's drums for it, with a
/// field to type the time instead. New tasks are written on the last line,
/// each half an hour after the one before.
struct NotchTasksView: View {
    @ObservedObject var service: NotchService
    @ObservedObject private var tasks = NotchTaskService.shared
    @ObservedObject private var l10n = L10n.shared
    @State private var draftText = ""
    @State private var draftMinutes = NotchTaskService.shared.draftMinutes
        ?? NotchTaskSupport.suggestedMinutes(now: Date())
    @State private var editingID: UUID?
    @State private var editingText = ""
    @State private var picking: Picking?
    @State private var typedTime = ""
    @State private var hoveredID: UUID?
    @FocusState private var focus: Field?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.notchSettingsPreview) private var preview
    private var text: NotchTaskStrings { FeatureStrings.notchTasks(l10n.language) }
    private static let rowHeight: CGFloat = 28
    private static let fontSize: CGFloat = 14
    private static let timeFont = NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .medium)

    private enum Field: Hashable {
        case draft
        case edit(UUID)
        case time
    }

    /// Whose time the drums are setting: a row, or the line being written.
    private struct Picking: Equatable {
        let id: UUID?
        var time: NotchTaskTime
    }

    private var interacting: Bool {
        picking != nil || editingID != nil || !draftText.isEmpty
    }

    /// Times sit in one column as wide as the widest of them, set against the
    /// dash, so every dash and every task starts at the same place.
    private var timeColumnWidth: CGFloat {
        let labels = tasks.tasks.map(\.minutes) + [draftMinutes]
        let widest = labels.map {
            (NotchTaskSupport.timeLabel($0) as NSString).size(withAttributes: [.font: Self.timeFont]).width
        }.max() ?? 0
        return widest.rounded(.up) + 1
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
        .onChange(of: interacting) { _, active in report(active) }
        .onDisappear {
            guard !preview else { return }
            tasks.interacting = false
            service.setPageLayer(.tasks, close: nil)
        }
    }

    /// Something half done keeps the island open, and Escape puts it away
    /// before it closes the island.
    private func report(_ active: Bool) {
        guard !preview else { return }
        tasks.interacting = active
        service.setPageLayer(.tasks, close: active ? { cancel() } : nil)
    }

    private func cancel() {
        if picking != nil {
            picking = nil
        } else if editingID != nil {
            editingID = nil
        } else {
            draftText = ""
        }
    }

    // MARK: - List

    private var list: some View {
        VStack(spacing: 6) {
            if tasks.tasks.isEmpty {
                NotchEmptyView(symbol: "checklist", message: text.empty)
            } else {
                ScrollView(.vertical) {
                    VStack(spacing: 2) {
                        ForEach(NotchTaskSupport.ordered(tasks.tasks)) { row($0) }
                    }
                }
                .scrollIndicators(.never)
            }
            if tasks.saveFailed {
                Label(text.saveFailed, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 10.5)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            composer
        }
    }

    private func row(_ task: NotchTask) -> some View {
        let editing = editingID == task.id
        let showsActions = !editing && hoveredID == task.id
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            timeButton(task.minutes) {
                openPicker(id: task.id, minutes: task.minutes)
            }
            dash
            if editing {
                TextField(text.placeholder, text: $editingText)
                    .textFieldStyle(.plain)
                    .font(.system(size: Self.fontSize))
                    .foregroundStyle(.white)
                    .focused($focus, equals: .edit(task.id))
                    .onSubmit { finishEditing(task.id) }
            } else {
                Button { toggle(task.id) } label: {
                    NotchStruckText(text: NotchTaskSupport.displayText(task.text), done: task.done,
                                    fontSize: Self.fontSize)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(NotchTaskSupport.rowText(task))
                .accessibilityHint(task.done ? text.markNotDone : text.markDone)
                .accessibilityAddTraits(task.done ? .isSelected : [])
            }
            if showsActions {
                HStack(spacing: 0) {
                    rowAction("pencil", title: text.edit) { beginEditing(task) }
                    rowAction("trash", title: text.delete) { delete(task.id) }
                }
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
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

    /// The line a new task is written on, with the time it will take. Its
    /// columns are the rows' columns.
    private var composer: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            timeButton(draftMinutes) {
                openPicker(id: nil, minutes: draftMinutes)
            }
            dash
            TextField(tasks.canAdd ? text.placeholder : String(format: text.limitFormat, NotchTaskSupport.maximumCount),
                      text: $draftText)
                .textFieldStyle(.plain)
                .font(.system(size: Self.fontSize))
                .foregroundStyle(.white)
                .focused($focus, equals: .draft)
                .disabled(!tasks.canAdd)
                .onSubmit(add)
                .accessibilityLabel(text.newTask)
            NotchIconButton(symbol: "plus", title: text.add, action: add)
                .disabled(!tasks.canAdd || NotchTaskSupport.sanitizedText(draftText) == nil)
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 5 }
        }
        .padding(.leading, 8)
        .frame(height: 32)
        .modifier(NotchControlSurface(cornerRadius: 10, interactive: false))
    }

    private func timeButton(_ minutes: Int, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(NotchTaskSupport.timeLabel(minutes))
                .font(Font(Self.timeFont))
                .foregroundStyle(.white)
                .frame(width: timeColumnWidth, alignment: .trailing)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(text.time)
        .accessibilityLabel(text.time)
        .accessibilityValue(NotchTaskSupport.timeLabel(minutes))
    }

    private var dash: some View {
        Text("—")
            .font(.system(size: Self.fontSize))
            .foregroundStyle(.white)
            .accessibilityHidden(true)
    }

    private func rowAction(_ symbol: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(NotchButtonStyle(cornerRadius: 7, lifts: false))
        .help(title)
        .accessibilityLabel(title)
    }

    // MARK: - Time

    private func openPicker(id: UUID?, minutes: Int) {
        typedTime = NotchTaskSupport.timeLabel(minutes)
        picking = Picking(id: id, time: NotchTaskTime(minutes: minutes))
        DispatchQueue.main.async { focus = .time }
    }

    /// The typed time, if the field holds one; an emptied field leaves the
    /// drums' time.
    private var typedMinutes: Int? {
        NotchTaskSupport.parseTime(typedTime, pm: picking?.time.pm ?? false)
    }

    private func picker(_ current: Picking) -> some View {
        let invalid = !typedTime.isEmpty && typedMinutes == nil
        return VStack(spacing: 8) {
            TextField(text.time, text: $typedTime)
                .textFieldStyle(.plain)
                .font(.system(size: 15, weight: .medium))
                .monospacedDigit()
                .multilineTextAlignment(.center)
                .foregroundStyle(invalid ? .red : .white)
                .focused($focus, equals: .time)
                .frame(width: 120, height: 28)
                .modifier(NotchControlSurface(cornerRadius: 8, interactive: false))
                .onSubmit(commitTime)
                .onChange(of: typedTime) { _, _ in
                    guard let minutes = typedMinutes, minutes != picking?.time.minutes else { return }
                    picking?.time = NotchTaskTime(minutes: minutes)
                }
                .accessibilityLabel(text.time)
            NotchTaskTimePicker(time: Binding(get: { picking?.time ?? current.time },
                                              set: { time in
                                                  picking?.time = time
                                                  typedTime = NotchTaskSupport.timeLabel(time.minutes)
                                              }),
                                text: text)
                .frame(maxWidth: .infinity, maxHeight: 150)
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
                .disabled(invalid)
            }
        }
        .frame(maxWidth: 300)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func commitTime() {
        guard var picking else { return }
        if let minutes = typedMinutes { picking.time = NotchTaskTime(minutes: minutes) }
        let minutes = picking.time.minutes
        if let id = picking.id {
            // A new time is the one change that moves a row, to its place in the day.
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) { tasks.update(id, minutes: minutes) }
        } else {
            setDraftMinutes(minutes)
        }
        self.picking = nil
        if picking.id == nil { DispatchQueue.main.async { focus = .draft } }
    }

    // MARK: - Actions

    private func add() {
        let minutes = draftMinutes
        var added = false
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) {
            added = tasks.add(minutes: minutes, text: draftText)
        }
        guard added else { return }
        draftText = ""
        setDraftMinutes(NotchTaskSupport.followingMinutes(after: minutes))
        focus = .draft
    }

    private func setDraftMinutes(_ minutes: Int) {
        draftMinutes = minutes
        tasks.draftMinutes = minutes
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
    let fontSize: CGFloat

    var body: some View {
        Text(text)
            .font(.system(size: fontSize))
            .lineLimit(1)
            .foregroundStyle(.white)
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(.white)
                    .frame(height: 1.5)
                    .scaleEffect(x: done ? 1 : 0, anchor: .leading)
            }
    }
}
