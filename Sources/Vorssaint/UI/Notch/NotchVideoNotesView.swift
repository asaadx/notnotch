// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// Notes on the YouTube video playing in Safari. The music player's row
/// heads the page: the video's frame with its glow, the title, the channel,
/// the time either side of the bar and the transport, which skips ten
/// seconds either way. Each note is a mark on the bar; pointing at a mark
/// lights its row and the other way round, and clicking either plays from
/// there. Below, the notes in the video's order and the line a new one is
/// written on, whose pill holds the moment typing began. "Safari ⌄" lists
/// the YouTube tabs, for when the notes follow the wrong one.
struct NotchVideoNotesView: View {
    @ObservedObject var service: NotchService
    @ObservedObject private var notes = NotchVideoNotesService.shared
    @ObservedObject private var music = NotchMusicService.shared
    @ObservedObject private var l10n = L10n.shared
    @State private var draft = ""
    /// The video's second when typing began, which the note is saved at.
    @State private var heldTime: Int?
    @State private var hovered: String?
    @State private var picking = false
    @State private var scrubPosition: Double?
    @State private var pendingSeek: UUID?
    @FocusState private var writing: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.notchSettingsPreview) private var preview
    private var text: NotchVideoNotesStrings { FeatureStrings.notchVideoNotes(l10n.language) }

    private static let playerHeight: CGFloat = 104
    private static let pillWidth: CGFloat = 50
    private static let secondaryColor = Color.white.opacity(0.55)
    private static let mutedColor = Color.white.opacity(0.4)

    private var accent: Color { notes.video.flatMap { notes.tints[$0.id] }?.color ?? .white }
    private var halo: Color { notes.video.flatMap { notes.tints[$0.id] }?.color ?? .clear }
    private var interacting: Bool { picking || !draft.isEmpty }

    var body: some View {
        Group {
            switch notes.access {
            case nil where !preview:
                Color.clear
            case .consent?:
                NotchEmptyView(symbol: "safari", message: text.safariAccess) {
                    NotchPillButton(title: text.allowSafari, prominent: true, action: notes.requestAccess)
                        .disabled(notes.requestingAccess)
                }
            case .denied?:
                NotchEmptyView(symbol: "safari", message: text.safariDenied) {
                    NotchPillButton(title: l10n.s.permissionOpenSettings, prominent: true) {
                        Permissions.shared.openAutomationSettings()
                    }
                }
            default:
                if picking || (notes.video == nil && notes.tabs.count > 1) {
                    picker.transition(.opacity)
                } else if let video = notes.video {
                    page(video).transition(.opacity)
                } else {
                    NotchEmptyView(symbol: "play.rectangle", message: text.nothingPlaying + "\n" + text.nothingPlayingHint)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(reduceMotion ? nil : .smooth(duration: 0.22), value: picking)
        .onAppear {
            guard !preview else { return }
            notes.pageVisible = true
        }
        .onChange(of: interacting) { _, active in report(active) }
        .onChange(of: picking) { _, open in if !preview { notes.pickerOpen = open } }
        .onChange(of: notes.video?.id) { _, _ in
            heldTime = nil
            hovered = nil
            scrubPosition = nil
        }
        .onDisappear {
            guard !preview else { return }
            notes.pageVisible = false
            notes.interacting = false
            service.setPageLayer(.videoNotes, close: nil)
        }
    }

    /// A note half written or the picker open keeps the island open, and
    /// Escape puts it away before it closes the island.
    private func report(_ active: Bool) {
        guard !preview else { return }
        notes.interacting = active
        service.setPageLayer(.videoNotes, close: active ? { cancel() } : nil)
    }

    private func cancel() {
        if picking {
            picking = false
        } else {
            draft = ""
            heldTime = nil
        }
    }

    // MARK: - Page

    private func page(_ video: NotchVideoNotesService.Video) -> some View {
        VStack(spacing: 0) {
            player(video)
            header
            list
            composer.padding(.top, 6)
            footer.padding(.top, 8)
        }
    }

    // MARK: - Player

    private func player(_ video: NotchVideoNotesService.Video) -> some View {
        HStack(spacing: 16) {
            Button(action: notes.showInSafari) {
                NotchArtwork(image: notes.thumbnails[video.id], size: Self.playerHeight)
                    .scaleEffect(notes.isPlaying || reduceMotion ? 1 : 0.94)
                    .shadow(color: halo.opacity(0.42), radius: 20, y: 7)
                    .shadow(color: halo.opacity(0.2), radius: 42, y: 14)
                    .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: notes.isPlaying)
                    .animation(reduceMotion ? nil : .smooth(duration: 0.45), value: halo)
            }
            .buttonStyle(NotchButtonStyle(cornerRadius: 24))
            .help(text.showInSafari)
            .accessibilityLabel(text.showInSafari)
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(video.title)
                            .font(.system(size: 16, weight: .semibold))
                            .lineLimit(1).help(video.title)
                        Spacer(minLength: 0)
                        sourceButton
                        if notes.isPlaying {
                            NotchLiveEqualizerBars(bars: 3, barWidth: 2.5, height: 12, tint: accent)
                                .transition(.opacity)
                        }
                    }
                    Text(video.channel ?? "YouTube")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                timeline
                transport.frame(maxWidth: .infinity)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .frame(height: Self.playerHeight)
    }

    /// "Safari ⌄", the player's source picker as the music page draws it.
    private var sourceButton: some View {
        Button { picking = true } label: {
            HStack(spacing: 2) {
                Text("Safari")
                Image(systemName: "chevron.down").font(.system(size: 7, weight: .semibold))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(.secondary)
        .help(text.chooseVideo)
        .accessibilityLabel(text.chooseVideo)
    }

    private var timeline: some View {
        TimelineView(.animation(minimumInterval: 1, paused: !notes.isPlaying)) { context in
            let duration = notes.duration
            let position = scrubPosition ?? notes.position(at: context.date) ?? 0
            HStack(spacing: 8) {
                // The video's longest reading holds each side's width, so the
                // bar keeps its length as it plays.
                ZStack(alignment: .leading) {
                    Text(label(duration)).hidden()
                    Text(label(position))
                }
                bar(position, duration: duration)
                ZStack(alignment: .trailing) {
                    Text("−" + label(duration)).hidden()
                    Text("−" + label(max(0, duration - position)))
                }
            }
            .font(.system(size: 10, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(.secondary)
        }
        .frame(height: 14)
        .task(id: pendingSeek) {
            guard pendingSeek != nil else { return }
            // The released thumb stays put while the player catches up.
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            scrubPosition = nil
            pendingSeek = nil
        }
    }

    private func bar(_ position: Double, duration: Double) -> some View {
        NotchLevelSlider(
            value: Binding(get: { position }, set: { scrubPosition = $0 }),
            label: FeatureStrings.notch(l10n.language).playbackPosition,
            range: 0...max(1, duration),
            tint: accent,
            valueLabel: label(position),
            onEditingChanged: { editing in
                if editing {
                    pendingSeek = nil
                } else if let scrubPosition {
                    notes.seek(to: scrubPosition)
                    pendingSeek = UUID()
                }
            })
            .frame(height: 10)
            .disabled(duration <= 0)
            .overlay { markers(duration: duration) }
    }

    /// One mark a note, drawn as the slider draws its own marker; pointing
    /// at it lights its row, and a click plays from it.
    private func markers(duration: Double) -> some View {
        GeometryReader { geometry in
            let track = max(0, geometry.size.width - 2)
            let height = max(1, geometry.size.height - 2 * max(1, geometry.size.height * 0.11))
            ForEach(duration > 0 ? notes.notes : []) { note in
                let lit = hovered == note.id
                Button { seek(note) } label: {
                    Rectangle()
                        .fill(.white.opacity(lit ? 1 : 0.45))
                        .frame(width: lit ? 2 : 1, height: height)
                        .scaleEffect(y: lit ? 1.25 : 1)
                        .frame(width: 11, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .position(x: 1 + track * NotchVideoNotesSupport.fraction(Double(note.t), duration: duration),
                          y: geometry.size.height / 2)
                .onHover { hovering in hover(note.id, hovering) }
                .help(note.text)
                .accessibilityLabel(text.playFrom(label(Double(note.t))))
                .accessibilityValue(note.text)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovered)
    }

    private var transport: some View {
        HStack(spacing: 12) {
            transportButton("backward.fill", size: 16, title: text.backward) { notes.skip(by: -10) }
            Button(action: notes.togglePlayback) {
                Image(systemName: notes.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .contentTransition(.symbolEffect(.replace))
                    .animation(reduceMotion ? nil : .smooth(duration: 0.22), value: notes.isPlaying)
                    .frame(width: 36, height: 36)
                    .contentShape(Circle())
            }
            .buttonStyle(NotchButtonStyle(cornerRadius: 18))
            .disabled(!notes.canToggle)
            .help(text.playPause)
            .accessibilityLabel(text.playPause)
            transportButton("forward.fill", size: 16, title: text.forward) { notes.skip(by: 10) }
        }
        .frame(height: 36)
    }

    private func transportButton(_ symbol: String, size: CGFloat, title: String,
                                 action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .contentShape(Circle())
        }
        .buttonStyle(NotchButtonStyle(cornerRadius: 18))
        .disabled(notes.position(at: Date()) == nil)
        .help(title)
        .accessibilityLabel(title)
    }

    // MARK: - Notes

    /// "Notes" and how many, as the tasks list heads its sections.
    private var header: some View {
        HStack {
            Text(text.notes)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Self.secondaryColor)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if !notes.notes.isEmpty {
                Text(text.count(notes.notes.count, agreement: l10n.language.countAgreement))
                    .font(.system(size: 12, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Self.mutedColor)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    private var list: some View {
        Group {
            if notes.notes.isEmpty {
                Text(text.empty)
                    .font(.system(size: 12))
                    .foregroundStyle(Self.mutedColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                Spacer(minLength: 0)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical) {
                        VStack(spacing: 2) {
                            ForEach(notes.notes) { row($0).id($0.id) }
                        }
                    }
                    .scrollIndicators(.never)
                    .notchScrollEdgeFade()
                    .onChange(of: hovered) { _, id in
                        guard let id, markerHover else { return }
                        withAnimation(reduceMotion ? nil : .smooth(duration: 0.2)) { proxy.scrollTo(id) }
                    }
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    /// Only a mark on the bar scrolls the list to its row.
    @State private var markerHover = false

    private func row(_ note: NotchVideoNote) -> some View {
        let lit = hovered == note.id
        return HStack(spacing: 12) {
            Button { seek(note) } label: {
                pill(label(Double(note.t)), lit: lit)
            }
            .buttonStyle(.plain)
            .help(text.playFrom(label(Double(note.t))))
            .accessibilityLabel(text.playFrom(label(Double(note.t))))
            Text(note.text)
                .font(.system(size: 14))
                .foregroundStyle(.white)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, 6)
        .padding(.trailing, 8)
        .padding(.vertical, 4)
        .frame(minHeight: 30)
        .background(.white.opacity(lit ? 0.06 : 0), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { seek(note) }
        .onHover { hovering in
            markerHover = false
            if hovering { hovered = note.id } else if hovered == note.id { hovered = nil }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    /// The grey time a row starts with; the line being written holds its own.
    private func pill(_ time: String, lit: Bool = false, held: Bool = false, faint: Bool = false) -> some View {
        Text(time)
            .font(.system(size: 11.5, weight: .semibold))
            .monospacedDigit()
            .lineLimit(1)
            .foregroundStyle(.white.opacity(lit || held ? 1 : faint ? 0.5 : 0.72))
            .frame(width: Self.pillWidth)
            .padding(.vertical, 2)
            .background(.white.opacity(lit ? 0.15 : held ? 0.16 : 0.08),
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    /// The line a note is written on. Its pill follows the video until typing
    /// starts, then holds that moment; Return saves the note there.
    private var composer: some View {
        HStack(spacing: 12) {
            TimelineView(.animation(minimumInterval: 1, paused: heldTime != nil || !notes.isPlaying)) { context in
                pill(label(Double(heldTime ?? Int(notes.position(at: context.date) ?? 0))),
                     held: heldTime != nil, faint: heldTime == nil)
            }
            .fixedSize()
            TextField(text.placeholder, text: $draft)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundStyle(.white)
                .focused($writing)
                .onSubmit(save)
                .accessibilityLabel(text.placeholder)
            Image(systemName: "return")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(draft.isEmpty ? 0.28 : 0.7))
                .accessibilityHidden(true)
        }
        .padding(.leading, 6)
        .padding(.trailing, 10)
        .frame(height: 32)
        .modifier(NotchControlSurface(cornerRadius: 10, interactive: false))
        .onChange(of: draft) { old, new in
            if new.count > NotchVideoNotesSupport.maximumTextLength {
                draft = String(new.prefix(NotchVideoNotesSupport.maximumTextLength))
            }
            if old.isEmpty, !new.isEmpty {
                heldTime = Int(notes.position(at: Date()) ?? 0)
            } else if new.isEmpty {
                heldTime = nil
            }
        }
    }

    private var footer: some View {
        let (symbol, message, warns): (String, String, Bool) = switch notes.syncState {
        case .saved: ("checkmark.icloud", text.saved, false)
        case .waiting: ("icloud.and.arrow.up", text.waiting, false)
        case .noKey: ("key", text.noKey, false)
        case .rejected: ("exclamationmark.triangle", text.rejected, true)
        }
        return Label(message, systemImage: symbol)
            .font(.system(size: 10.5))
            .foregroundStyle(warns ? Color.orange : Self.mutedColor)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
    }

    // MARK: - Picker

    private var picker: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                if notes.video != nil {
                    NotchIconButton(symbol: "chevron.left", title: text.back) { picking = false }
                }
                Text(text.playingInSafari)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                Spacer(minLength: 8)
                Text(text.pickerHint)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
            }
            .frame(minHeight: 28)
            if notes.tabs.isEmpty {
                NotchEmptyView(symbol: "play.rectangle", message: text.nothingPlaying)
            } else {
                ScrollView(.vertical) {
                    VStack(spacing: 2) {
                        ForEach(notes.tabs, id: \.self) { pickRow($0) }
                    }
                }
                .scrollIndicators(.never)
                .notchScrollEdgeFade()
            }
        }
    }

    private func pickRow(_ tab: NotchSafariTab) -> some View {
        let id = tab.videoID ?? ""
        let state = notes.tabStates[id]
        let current = notes.video?.id == id
        return Button {
            notes.pick(tab)
            picking = false
        } label: {
            HStack(spacing: 12) {
                Group {
                    if let image = notes.thumbnail(for: tab) {
                        Image(nsImage: image).resizable().scaledToFill()
                    } else {
                        Color.white.opacity(0.06)
                    }
                }
                .frame(width: 76, height: 43)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(tab.videoTitle.isEmpty ? tab.url : tab.videoTitle)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(state?.channel ?? (current ? notes.video?.channel : nil) ?? "YouTube")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let state {
                    HStack(spacing: 6) {
                        Image(systemName: state.paused ? "pause.fill" : "speaker.wave.2.fill")
                            .font(.system(size: 10))
                        Text(label(state.position(at: Date()))).monospacedDigit()
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(Self.secondaryColor)
                }
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .opacity(current ? 1 : 0)
                    .frame(width: 16)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(NotchButtonStyle(cornerRadius: 12, lifts: false))
        .accessibilityAddTraits(current ? .isSelected : [])
    }

    // MARK: - Actions

    private func hover(_ id: String, _ hovering: Bool) {
        markerHover = hovering
        if hovering { hovered = id } else if hovered == id { hovered = nil }
    }

    private func seek(_ note: NotchVideoNote) {
        scrubPosition = nil
        notes.seek(to: Double(note.t))
    }

    private func save() {
        guard !NotchVideoNotesSupport.isBlank(draft) else { return }
        let t = heldTime ?? Int(notes.position(at: Date()) ?? 0)
        guard notes.add(draft, at: t) else { return }
        draft = ""
        heldTime = nil
        writing = true
    }

    private func label(_ seconds: Double) -> String {
        NotchVideoNotesSupport.timeLabel(seconds)
    }
}

/// Jarvis in the page's settings: its address and the key the notes go with.
struct NotchVideoNotesSettingsControls: View {
    @ObservedObject private var notes = NotchVideoNotesService.shared
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.notchVideoNotesBaseURL) private var baseURL = NotchVideoNotesSupport.defaultBaseURL
    @State private var key = ""
    private var text: NotchVideoNotesStrings { FeatureStrings.notchVideoNotes(l10n.language) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Jarvis").font(.subheadline.weight(.medium))
            Text(text.settingsHint).font(.caption).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                TextField(text.address, text: $baseURL)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(notes.settingsChanged)
                if NotchVideoNotesSupport.baseURL(from: baseURL) == nil {
                    Text(text.invalidAddress).font(.caption).foregroundStyle(.orange)
                }
            }
            if notes.hasKey {
                HStack(spacing: 8) {
                    status
                    Spacer(minLength: 0)
                    Button(text.removeKey, action: notes.removeKey)
                }
                if notes.keyRejected { keyField }
            } else {
                keyField
            }
            Text(text.javaScriptHint).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onDisappear(perform: notes.settingsChanged)
    }

    private var keyField: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                SecureField(text.apiKey, text: $key)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(save)
                Button(text.saveKey, action: save)
                    .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Text(text.keySaved).font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var status: some View {
        switch notes.syncState {
        case .saved, .noKey:
            Label(text.saved, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .waiting:
            Label(text.waiting, systemImage: "icloud.and.arrow.up").foregroundStyle(.secondary)
        case .rejected:
            Label(text.rejected, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
    }

    private func save() {
        guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        notes.setKey(key)
        key = ""
    }
}
