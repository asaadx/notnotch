// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// A short to-do list in the island in the manner of Reminders, one line a
/// task: a circle to finish it, its words, and its time at the trailing edge,
/// read by time of day. The circle fills and the words are struck through,
/// and the row stays where it is; clicking the words edits them, and clicking
/// the time turns up the Clock's drums for it, with a field to type the time
/// instead. New tasks are written on the last line, each half an hour after
/// the one before. Timed tasks read under "kill list" and tasks with no time,
/// which come from Todoist, under "whenever"; Todoist tasks left open from
/// earlier days lead under "overdue", with the day they were due in red.
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
    @State private var dropTarget: Section?
    @FocusState private var focus: Field?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.notchSettingsPreview) private var preview
    private var text: NotchTaskStrings { FeatureStrings.notchTasks(l10n.language) }
    private static let rowHeight: CGFloat = 28
    private static let fontSize: CGFloat = 14
    private static let timeFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
    private static let secondaryColor = Color.white.opacity(0.55)
    private static let mutedColor = Color.white.opacity(0.4)
    private static let markSize: CGFloat = 18

    private enum Field: Hashable {
        case draft
        case edit(UUID)
        case time
    }

    /// The list's parts. A task dragged to the kill list is given a time, and
    /// one dragged to whenever loses it; nothing is dragged into overdue.
    private enum Section: Hashable {
        case overdue, timed, anytime
    }

    /// Whose time the drums are setting: a row, or the line being written.
    private struct Picking: Equatable {
        let id: UUID?
        var time: NotchTaskTime
    }

    private var interacting: Bool {
        picking != nil || editingID != nil || !draftText.isEmpty
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
        .onAppear {
            tasks.load()
            if !preview { NotchTodoistService.shared.pageVisible = true }
        }
        .onChange(of: interacting) { _, active in report(active) }
        .onDisappear {
            guard !preview else { return }
            NotchTodoistService.shared.pageVisible = false
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
                    VStack(spacing: 0) {
                        let overdue = NotchTaskSupport.overdue(tasks.tasks)
                        // The kill list and whenever stay, empty or not, so a
                        // task can always be dragged to either.
                        if !overdue.isEmpty { section(.overdue, overdue, first: true) }
                        section(.timed, NotchTaskSupport.ordered(tasks.tasks), first: overdue.isEmpty)
                        section(.anytime, NotchTaskSupport.anytime(tasks.tasks), first: false)
                    }
                }
                .scrollIndicators(.never)
                .notchScrollEdgeFade()
            }
            if tasks.saveFailed {
                Label(text.saveFailed, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 10.5)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            composer
        }
    }

    private func section(_ section: Section, _ rows: [NotchTask], first: Bool) -> some View {
        let title = section == .overdue ? text.overdue : section == .timed ? text.killList : text.whenever
        return VStack(spacing: 2) {
            sectionHeader(title, first: first, tint: section == .overdue ? .red : Self.secondaryColor)
            ForEach(rows) { row($0) }
        }
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, minHeight: rows.isEmpty ? Self.rowHeight : nil, alignment: .top)
        .background(.white.opacity(dropTarget == section ? 0.06 : 0),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .dropDestination(for: String.self) { ids, _ in
            guard let id = ids.first.flatMap(UUID.init(uuidString:)) else { return false }
            return drop(id, on: section)
        } isTargeted: { targeted in
            if targeted { dropTarget = section } else if dropTarget == section { dropTarget = nil }
        }
    }

    /// A task dropped on the kill list is given a time with the drums; one
    /// dropped on whenever loses its time.
    private func drop(_ id: UUID, on section: Section) -> Bool {
        guard let task = tasks.tasks.first(where: { $0.id == id }), tasks.canRetime(task) else { return false }
        switch section {
        case .overdue:
            return false
        case .timed:
            guard task.minutes == nil else { return false }
            openPicker(id: id, minutes: NotchTaskSupport.suggestedMinutes(now: Date()))
            return true
        case .anytime:
            guard task.minutes != nil || NotchTodoistSupport.isOverdue(task) else { return false }
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) { tasks.setTime(id, minutes: nil) }
            return true
        }
    }

    private func row(_ task: NotchTask) -> some View {
        let editing = editingID == task.id
        let showsActions = !editing && hoveredID == task.id
        let struck = task.done && !editing
        return HStack(spacing: 8) {
            checkmark(task)
            if editing {
                TextField(text.placeholder, text: $editingText)
                    .textFieldStyle(.plain)
                    .font(.system(size: Self.fontSize))
                    .foregroundStyle(.white)
                    .focused($focus, equals: .edit(task.id))
                    .onSubmit { finishEditing(task.id) }
            } else {
                Text(NotchTaskSupport.displayText(task.text))
                    .font(.system(size: Self.fontSize))
                    .lineLimit(1)
                    .foregroundStyle(struck ? Self.mutedColor : .white)
                    .overlay(alignment: .leading) { strike(struck) }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { beginEditing(task) }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint(text.edit)
            }
            if showsActions {
                if task.minutes == nil, !NotchTodoistSupport.isOverdue(task), tasks.canRetime(task) {
                    rowAction("clock", title: text.time) { openPicker(id: task.id, minutes: suggestedMinutes) }
                }
                rowAction("trash", title: text.delete) { delete(task.id) }
            }
            detail(task, muted: struck)
        }
        .padding(.horizontal, 8)
        .frame(height: Self.rowHeight)
        .background(.white.opacity(hoveredID == task.id || editing ? 0.06 : 0),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onHover { hovering in
            if hovering { hoveredID = task.id } else if hoveredID == task.id { hoveredID = nil }
        }
        .modifier(TaskDrag(task: task, enabled: !editing))
        .contextMenu {
            Button(text.edit) { beginEditing(task) }
            Button(task.done ? text.markNotDone : text.markDone) { toggle(task.id) }
            if tasks.canRetime(task) {
                Button(text.time) { openPicker(id: task.id, minutes: task.minutes ?? suggestedMinutes) }
                if task.minutes != nil || NotchTodoistSupport.isOverdue(task) {
                    Button(text.removeTime) { tasks.setTime(task.id, minutes: nil) }
                }
            }
            Divider()
            Button(text.delete, role: .destructive) { delete(task.id) }
        }
    }

    /// The circle a task is finished with, filled in the accent once done.
    private func checkmark(_ task: NotchTask) -> some View {
        Button { toggle(task.id) } label: {
            Image(systemName: task.done ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 15))
                .foregroundStyle(task.done ? Color.orange : Self.mutedColor)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: Self.markSize, height: Self.markSize)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(NotchTaskSupport.rowText(task))
        .accessibilityHint(task.done ? text.markNotDone : text.markDone)
        .accessibilityAddTraits(task.done ? .isSelected : [])
    }

    /// What trails a row: its time, or for an overdue task the day it was
    /// due, in red.
    @ViewBuilder private func detail(_ task: NotchTask, muted: Bool) -> some View {
        if let minutes = task.minutes {
            timeButton(minutes, muted: muted, enabled: tasks.canRetime(task)) {
                openPicker(id: task.id, minutes: minutes)
            }
        } else if let link = task.todoist, NotchTodoistSupport.isOverdue(task),
                  let due = NotchTodoistSupport.overdueLabel(link, locale: Locale(identifier: l10n.language.rawValue)) {
            // Clicking it gives the task a time today.
            let retimes = tasks.canRetime(task)
            Button { if retimes { openPicker(id: task.id, minutes: suggestedMinutes) } } label: {
                Text(NotchTaskSupport.displayText(due))
                    .font(.system(size: 12))
                    .foregroundStyle(muted ? Self.mutedColor : .red)
                    .fixedSize()
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(retimes ? text.time : text.repeatingTime)
        }
    }

    /// Where the drums start for a task that has no time yet.
    private var suggestedMinutes: Int {
        NotchTaskSupport.suggestedMinutes(now: Date())
    }

    /// The line a new task is written on, with the time it will take. Its
    /// columns are the rows' columns: the add button where their circles are.
    private var composer: some View {
        let canSubmit = tasks.canAdd && NotchTaskSupport.sanitizedText(draftText) != nil
        return HStack(spacing: 8) {
            Button(action: add) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(.orange)
                    .opacity(canSubmit ? 1 : 0.45)
                    .frame(width: Self.markSize, height: Self.markSize)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit)
            .help(text.add)
            .accessibilityLabel(text.add)
            TextField(tasks.canAdd ? text.placeholder : String(format: text.limitFormat, NotchTaskSupport.maximumCount),
                      text: $draftText)
                .textFieldStyle(.plain)
                .font(.system(size: Self.fontSize))
                .foregroundStyle(.white)
                .focused($focus, equals: .draft)
                .disabled(!tasks.canAdd)
                .onSubmit(add)
                .accessibilityLabel(text.newTask)
            timeButton(draftMinutes) {
                openPicker(id: nil, minutes: draftMinutes)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 32)
        .modifier(NotchControlSurface(cornerRadius: 10, interactive: false))
    }

    /// A repeating Todoist task's time reads the same but is changed in
    /// Todoist, where its repeat is.
    private func timeButton(_ minutes: Int, muted: Bool = false, enabled: Bool = true,
                            action: @escaping () -> Void) -> some View {
        Button { if enabled { action() } } label: {
            Text(NotchTaskSupport.timeLabel(minutes))
                .font(Font(Self.timeFont))
                .foregroundStyle(muted ? Self.mutedColor : Self.secondaryColor)
                .fixedSize()
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(enabled ? text.time : text.repeatingTime)
        .accessibilityLabel(text.time)
        .accessibilityValue(NotchTaskSupport.timeLabel(minutes))
    }

    /// A list's header in the manner of Reminders: short, bold, leading;
    /// red for what is overdue.
    private func sectionHeader(_ title: String, first: Bool, tint: Color = secondaryColor) -> some View {
        Text(NotchTaskSupport.displayText(title))
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.top, first ? 2 : 10)
            .padding(.bottom, 2)
            .accessibilityAddTraits(.isHeader)
    }

    /// A line drawn across a done task's words from the leading edge, and
    /// drawn back as it is undone.
    private func strike(_ done: Bool) -> some View {
        Capsule()
            .fill(Self.mutedColor)
            .frame(height: 1.5)
            .scaleEffect(x: done ? 1 : 0, anchor: .leading)
            .allowsHitTesting(false)
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
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) { tasks.setTime(id, minutes: minutes) }
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
        setDraftMinutes(tasks.draftMinutes ?? NotchTaskSupport.followingMinutes(after: minutes))
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

/// Todoist in the list's settings: the API token, and how the last sync went.
struct NotchTodoistSettingsControls: View {
    @ObservedObject private var todoist = NotchTodoistService.shared
    @ObservedObject private var l10n = L10n.shared
    @State private var token = ""
    private var text: NotchTaskStrings { FeatureStrings.notchTasks(l10n.language) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Todoist").font(.subheadline.weight(.medium))
            Text(text.todoistHint).font(.caption).foregroundStyle(.secondary)
            if todoist.connected {
                HStack(spacing: 8) {
                    status
                    Spacer(minLength: 0)
                    Button(text.todoistDisconnect, action: todoist.disconnect)
                }
                if todoist.status == .rejected { tokenField }
            } else {
                tokenField
            }
        }
    }

    private var tokenField: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                SecureField(text.todoistToken, text: $token)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(connect)
                Button(text.todoistConnect, action: connect)
                    .disabled(token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            HStack(spacing: 8) {
                Text(text.todoistTokenHint).font(.caption).foregroundStyle(.secondary)
                Link(text.todoistGetToken, destination: NotchTodoistSupport.tokenPage).font(.caption)
            }
        }
    }

    @ViewBuilder private var status: some View {
        switch todoist.status {
        case .off, .connecting:
            Label(text.todoistConnecting, systemImage: "arrow.triangle.2.circlepath").foregroundStyle(.secondary)
        case .synced:
            Label(text.todoistConnected, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .offline:
            Label(text.todoistOffline, systemImage: "wifi.exclamationmark").foregroundStyle(.secondary)
        case .rejected:
            Label(text.todoistRejected, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
    }

    private func connect() {
        guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        todoist.connect(token)
        token = ""
    }
}

/// A row carries its task's id when dragged, as a capsule of its words; a
/// row being edited keeps the mouse for its text.
private struct TaskDrag: ViewModifier {
    let task: NotchTask
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.draggable(task.id.uuidString) {
                Text(NotchTaskSupport.displayText(task.text))
                    .font(.system(size: 14))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.black.opacity(0.85), in: Capsule())
            }
        } else {
            content
        }
    }
}
