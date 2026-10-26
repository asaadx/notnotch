// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import Foundation
import os.log
import Security

/// Notes on the YouTube video playing in Safari, sent to Jarvis with the
/// moment they were written. Now Playing names the video and its time; the
/// Safari tab with that title gives its address. Where Safari allows
/// JavaScript from Apple Events, the page's own player gives the exact time
/// and seeks in place; otherwise a seek reloads the video at that second.
///
/// A note is queued on disk before it is sent and leaves the queue only once
/// Jarvis has stored it, so a note written offline, or one whose answer was
/// lost, goes again with the same client id and is stored once.
final class NotchVideoNotesService: ObservableObject {
    static let shared = NotchVideoNotesService()

    /// The video the notes are for.
    struct Video: Equatable {
        let id: String
        let url: String
        let title: String
        let channel: String?
        let tab: NotchSafariTab
    }

    enum SyncState: Equatable {
        case saved, waiting, noKey, rejected
    }

    /// Nil until Safari has been asked once.
    @Published private(set) var access: NotchSafariTabs.Access?
    /// Safari's YouTube video tabs, each video once.
    @Published private(set) var tabs: [NotchSafariTab] = []
    @Published private(set) var video: Video?
    /// The page's own player, where JavaScript reaches it.
    @Published private(set) var state: NotchVideoState?
    /// Nil until Safari has been asked; false while it refuses JavaScript.
    @Published private(set) var javaScriptAllowed: Bool?
    /// Each listed tab's player, by video id, while the picker shows.
    @Published private(set) var tabStates: [String: NotchVideoState] = [:]
    @Published private(set) var notes: [NotchVideoNote] = []
    @Published private(set) var thumbnails: [String: NSImage] = [:]
    @Published private(set) var tints: [String: NotchArtworkTint] = [:]
    @Published private(set) var queued: [NotchVideoNotesPending]
    @Published private(set) var hasKey: Bool
    @Published private(set) var keyRejected = false
    @Published private(set) var requestingAccess = false
    /// A note is being written. The island stays open around it.
    @Published var interacting = false

    var pageVisible = false {
        didSet {
            guard pageVisible != oldValue else { return }
            pageVisible ? start() : stop()
        }
    }

    var pickerOpen = false {
        didSet { if pickerOpen && !oldValue { refreshPickerStates() } }
    }

    var syncState: SyncState {
        if !hasKey { return .noKey }
        if keyRejected { return .rejected }
        return queued.isEmpty ? .saved : .waiting
    }

    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "vorssaint", category: "VideoNotes")
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        return URLSession(configuration: configuration)
    }()
    /// Apple Events to Safari wait for its reply; one at a time, off the main thread.
    private let safari = DispatchQueue(label: "com.vorssaint.utils.video-notes.safari", qos: .userInitiated)
    private let store = NotchVideoNotesQueueStore(directoryURL: PrivateFileStore.containerURL)
    private let music = NotchMusicService.shared
    private var key: String?
    private var pinnedVideoID: String?
    private var serverNotes: [String: [NotchVideoNote]] = [:]
    private var storedNotes: [String: [NotchVideoNote]] = [:]
    private var sending: String?
    private var failures = 0
    private var retry: Timer?
    private var poll: Timer?
    private var ticks = 0
    private var inFlight = 0
    private var loadingThumbnails = Set<String>()
    private var subscriptions = Set<AnyCancellable>()

    private init() {
        key = NotchVideoNotesKeychain.read()
        hasKey = key != nil
        queued = store.load()
        // A new title from Now Playing may be another video, or the one a
        // tab was waiting to be matched with.
        music.$playback
            .map { $0?.track.title }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.titleChanged() }
            .store(in: &subscriptions)
        if !queued.isEmpty { DispatchQueue.main.async { [weak self] in self?.flush() } }
    }

    // MARK: - Lifecycle

    private func start() {
        ticks = 0
        refreshTabs()
        flush()
        if let video { loadNotes(video) }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        poll = timer
    }

    private func stop() {
        poll?.invalidate()
        poll = nil
        pickerOpen = false
        tabStates = [:]
    }

    /// Every second the player's time; every third Safari's tabs, which can
    /// change under it. A Safari that refused JavaScript is asked again now
    /// and then, in case the setting was turned on.
    private func tick() {
        ticks += 1
        if ticks % 3 == 0 || access != .granted {
            refreshTabs()
        } else if video != nil, javaScriptAllowed != false || ticks % 15 == 1 {
            refreshState()
        }
        if pickerOpen, ticks % 2 == 0 { refreshPickerStates() }
    }

    // MARK: - Safari

    func requestAccess() {
        guard !requestingAccess else { return }
        requestingAccess = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            NotchSafariTabs.requestAccess()
            DispatchQueue.main.async {
                self?.requestingAccess = false
                self?.refreshTabs()
            }
        }
    }

    private func refreshTabs() {
        guard inFlight < 2 else { return }
        inFlight += 1
        safari.async { [weak self] in
            let access = NotchSafariTabs.access()
            let tabs = access == .granted ? NotchSafariTabs.tabs() : []
            DispatchQueue.main.async {
                guard let self else { return }
                self.inFlight -= 1
                if self.access != access { self.access = access }
                guard let tabs else { return }
                let videos = NotchVideoNotesSupport.videoTabs(tabs)
                if videos != self.tabs { self.tabs = videos }
                self.reselect()
            }
        }
    }

    private func refreshState() {
        guard let tab = video?.tab, inFlight < 2 else { return }
        inFlight += 1
        safari.async { [weak self] in
            let (reply, state) = NotchSafariTabs.state(of: tab)
            DispatchQueue.main.async {
                guard let self else { return }
                self.inFlight -= 1
                self.receive(reply)
                guard self.video?.tab == tab else { return }
                if case .ok = reply {
                    self.state = state
                    // The channel shows under the title once the page names it.
                    if let video = self.video, video.channel == nil, let channel = state?.channel {
                        self.video = Video(id: video.id, url: video.url, title: video.title, channel: channel, tab: video.tab)
                    }
                }
            }
        }
    }

    private func refreshPickerStates() {
        guard javaScriptAllowed == true, inFlight < 2 else { return }
        let tabs = self.tabs
        inFlight += 1
        safari.async { [weak self] in
            var states: [String: NotchVideoState] = [:]
            for tab in tabs {
                if let id = tab.videoID, let state = NotchSafariTabs.state(of: tab).state { states[id] = state }
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.inFlight -= 1
                if self.pickerOpen { self.tabStates = states }
            }
        }
    }

    private func receive(_ reply: NotchSafariTabs.Reply) {
        switch reply {
        case .ok: if javaScriptAllowed != true { javaScriptAllowed = true }
        case .javaScriptOff:
            if javaScriptAllowed != false { javaScriptAllowed = false }
            state = nil
        case .denied, .failed: break
        }
    }

    private func titleChanged() {
        guard pageVisible else { return }
        reselect()
        refreshTabs()
    }

    /// The tab the notes follow. Changing video drops the old player's
    /// reading and asks Jarvis for the new one's notes.
    private func reselect() {
        if let pinned = pinnedVideoID, access == .granted, !tabs.contains(where: { $0.videoID == pinned }) {
            pinnedVideoID = nil
        }
        let playing = music.playback?.track
        guard let tab = NotchVideoNotesSupport.selectedTab(in: tabs, pinnedVideoID: pinnedVideoID,
                                                           nowPlayingTitle: playing?.title),
              let id = tab.videoID else {
            if video != nil { video = nil; state = nil; notes = [] }
            return
        }
        let matched = NotchVideoNotesSupport.sameTitle(playing?.title, tab.videoTitle)
        let title = tab.videoTitle.isEmpty ? (matched ? playing?.title : nil) ?? "" : tab.videoTitle
        let channel = (matched ? playing?.artist : nil) ?? (video?.id == id ? video?.channel : nil)
        let next = Video(id: id, url: NotchVideoNotesSupport.canonicalURL(videoID: id), title: title,
                         channel: channel?.isEmpty == false ? channel : nil, tab: tab)
        guard next != video else { return }
        let changed = next.id != video?.id
        video = next
        guard changed else { return }
        state = nil
        rebuildNotes()
        loadNotes(next)
        loadThumbnail(id)
        refreshState()
    }

    /// Notes follow this tab until its video closes, unless it is the one
    /// Now Playing would choose anyway.
    func pick(_ tab: NotchSafariTab) {
        let automatic = NotchVideoNotesSupport.matchingTab(nowPlayingTitle: music.playback?.track.title, in: tabs)
        pinnedVideoID = automatic?.videoID == tab.videoID ? nil : tab.videoID
        reselect()
    }

    func showInSafari() {
        guard let tab = video?.tab else { return }
        safari.async { NotchSafariTabs.show(tab) }
    }

    // MARK: - Playback

    /// Now Playing's reading, when it is this video.
    var matchedPlayback: NotchPlayback? {
        guard let playback = music.playback, let video,
              NotchVideoNotesSupport.sameTitle(playback.track.title, video.title) else { return nil }
        return playback
    }

    func position(at date: Date) -> Double? {
        if let state { return state.position(at: date) }
        return matchedPlayback?.position(at: date)
    }

    var duration: Double {
        if let state, state.duration > 0 { return state.duration }
        return matchedPlayback?.duration ?? 0
    }

    var isPlaying: Bool {
        if let state { return !state.paused }
        return matchedPlayback?.isPlaying ?? false
    }

    var canToggle: Bool {
        guard video != nil else { return false }
        return javaScriptAllowed != false || music.canPerform(.toggle) && matchedPlayback != nil
    }

    /// In place through the page's player where Safari allows it, else
    /// through Now Playing, else by opening the video at that second.
    func seek(to seconds: Double) {
        guard let video else { return }
        let target = duration > 0 ? min(duration, max(0, seconds)) : max(0, seconds)
        guard javaScriptAllowed != false else { fallbackSeek(target, video: video); return }
        if var state {
            state.time = target
            state.sampledAt = Date()
            self.state = state
        }
        let tab = video.tab
        safari.async { [weak self] in
            let reply = NotchSafariTabs.javaScript(NotchVideoNotesSupport.seekJavaScript(target), in: tab)
            DispatchQueue.main.async {
                guard let self else { return }
                self.receive(reply)
                if reply == .javaScriptOff, self.video == video { self.fallbackSeek(target, video: video) }
            }
        }
    }

    private func fallbackSeek(_ target: Double, video: Video) {
        if let playback = matchedPlayback, music.canSeek, let context = playback.commandContext {
            music.seek(to: target, in: playback.track, context: context)
            return
        }
        let url = NotchVideoNotesSupport.seekURL(videoID: video.id, seconds: target)
        safari.async { NotchSafariTabs.open(url, in: video.tab) }
    }

    func skip(by seconds: Double) {
        guard let now = position(at: Date()) else { return }
        seek(to: now + seconds)
    }

    func togglePlayback() {
        guard let video else { return }
        guard javaScriptAllowed != false else {
            if let playback = matchedPlayback { music.send(.toggle, context: playback.commandContext) }
            return
        }
        if var state {
            state.time = state.position(at: Date())
            state.sampledAt = Date()
            state.paused.toggle()
            self.state = state
        }
        safari.async { [weak self] in
            let reply = NotchSafariTabs.javaScript(NotchVideoNotesSupport.toggleJavaScript, in: video.tab)
            DispatchQueue.main.async {
                guard let self else { return }
                self.receive(reply)
                if reply == .javaScriptOff, let playback = self.matchedPlayback {
                    self.music.send(.toggle, context: playback.commandContext)
                }
                self.refreshState()
            }
        }
    }

    // MARK: - Notes

    /// Queues the note as typed, at `t` seconds, and sends it.
    @discardableResult
    func add(_ text: String, at t: Int) -> Bool {
        guard let video, !NotchVideoNotesSupport.isBlank(text),
              text.count <= NotchVideoNotesSupport.maximumTextLength,
              queued.count < NotchVideoNotesSupport.maximumQueued else { return false }
        let note = NotchVideoNotesPending(clientId: UUID().uuidString.lowercased(), url: video.url,
                                          title: video.title.isEmpty ? video.url : video.title,
                                          channel: video.channel, t: max(0, t), text: text, createdAt: Date())
        queued.append(note)
        if !store.save(queued) { Self.log.error("video notes queue could not be written") }
        rebuildNotes()
        flush()
        return true
    }

    /// Sends the oldest waiting note, then the next, until the queue is
    /// empty or a send fails; a failure waits longer each time.
    func flush() {
        retry?.invalidate()
        retry = nil
        guard sending == nil, !keyRejected, let pending = queued.first,
              let key, let base = Self.baseURL,
              let request = NotchVideoNotesSupport.postRequest(baseURL: base, key: key, note: pending) else { return }
        sending = pending.clientId
        session.dataTask(with: request) { [weak self] data, response, error in
            let outcome = NotchVideoNotesSupport.outcome(status: (response as? HTTPURLResponse)?.statusCode, data: data)
            if let error { Self.log.notice("video note not sent: \(error.localizedDescription, privacy: .public)") }
            DispatchQueue.main.async { self?.finishSending(pending, outcome: outcome, key: key) }
        }.resume()
    }

    private func finishSending(_ pending: NotchVideoNotesPending, outcome: NotchVideoNotesOutcome, key: String) {
        sending = nil
        guard key == self.key else { flush(); return }
        let next = NotchVideoNotesSupport.queue(queued, after: outcome, for: pending.clientId)
        if next != queued {
            queued = next
            store.save(queued)
        }
        switch outcome {
        case .stored(let note):
            failures = 0
            storedNotes[pending.url, default: []].append(note ?? NotchVideoNote(
                id: pending.clientId, t: pending.t, text: pending.text, createdAt: pending.createdAt))
            rebuildNotes()
            flush()
        case .rejectedKey:
            keyRejected = true
        case .failed:
            failures += 1
            let timer = Timer(timeInterval: NotchVideoNotesSupport.backoff(failures: failures), repeats: false) { [weak self] _ in
                self?.flush()
            }
            RunLoop.main.add(timer, forMode: .common)
            retry = timer
        }
    }

    private func loadNotes(_ video: Video) {
        guard let key, let base = Self.baseURL,
              let request = NotchVideoNotesSupport.notesRequest(baseURL: base, key: key, videoURL: video.url) else { return }
        session.dataTask(with: request) { [weak self] data, response, _ in
            let status = (response as? HTTPURLResponse)?.statusCode
            let notes = status == 200 ? data.flatMap(NotchVideoNotesSupport.notes(fromListReply:)) : nil
            DispatchQueue.main.async {
                guard let self else { return }
                if status == 401 || status == 403 { self.keyRejected = true }
                guard let notes else { return }
                self.serverNotes[video.url] = notes
                self.storedNotes[video.url] = nil
                if self.video?.url == video.url { self.rebuildNotes() }
            }
        }.resume()
    }

    private func rebuildNotes() {
        guard let video else { notes = []; return }
        let next = NotchVideoNotesSupport.displayNotes(server: serverNotes[video.url] ?? [], stored: storedNotes[video.url] ?? [],
                                                       queue: queued, videoURL: video.url)
        if next != notes { notes = next }
    }

    // MARK: - Thumbnails

    private func loadThumbnail(_ id: String) {
        guard thumbnails[id] == nil, loadingThumbnails.insert(id).inserted,
              let url = NotchVideoNotesSupport.thumbnailURL(videoID: id) else { return }
        session.dataTask(with: url) { [weak self] data, _, _ in
            let image = data.flatMap(NSImage.init(data:)).map(Self.widescreen)
            let tint = image.flatMap(Self.tint)
            DispatchQueue.main.async {
                guard let self else { return }
                self.loadingThumbnails.remove(id)
                guard let image else { return }
                self.thumbnails[id] = image
                if let tint { self.tints[id] = tint }
            }
        }.resume()
    }

    func thumbnail(for tab: NotchSafariTab) -> NSImage? {
        guard let id = tab.videoID else { return nil }
        if thumbnails[id] == nil { loadThumbnail(id) }
        return thumbnails[id]
    }

    /// YouTube's 4:3 still letterboxes a 16:9 frame; only the frame is kept.
    private static func widescreen(_ image: NSImage) -> NSImage {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return image }
        let width = cgImage.width, height = cgImage.height
        let band = Int((Double(width) * 9 / 16).rounded())
        guard band > 0, band < height,
              let cropped = cgImage.cropping(to: CGRect(x: 0, y: (height - band) / 2, width: width, height: band)) else { return image }
        return NSImage(cgImage: cropped, size: NSSize(width: width, height: band))
    }

    /// The frame's average colour, for the halo, as the music player takes it.
    private static func tint(_ image: NSImage) -> NotchArtworkTint? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        let drawn = pixel.withUnsafeMutableBytes { buffer -> Bool in
            guard let base = buffer.baseAddress,
                  let context = CGContext(data: base, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        guard drawn else { return nil }
        return NotchArtworkTint.from(red: Double(pixel[0]) / 255, green: Double(pixel[1]) / 255, blue: Double(pixel[2]) / 255)
    }

    // MARK: - Settings

    static var baseURL: URL? {
        NotchVideoNotesSupport.baseURL(from: UserDefaults.standard.string(forKey: DefaultsKey.notchVideoNotesBaseURL)
            ?? NotchVideoNotesSupport.defaultBaseURL)
    }

    /// Keeps the key in the Keychain and sends what was waiting.
    func setKey(_ key: String) {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        if !NotchVideoNotesKeychain.save(key) { Self.log.error("video notes key could not be kept in the keychain") }
        self.key = key
        hasKey = true
        settingsChanged()
    }

    func removeKey() {
        NotchVideoNotesKeychain.delete()
        key = nil
        hasKey = false
        keyRejected = false
        retry?.invalidate()
        retry = nil
    }

    /// A new address or key: try again from the start.
    func settingsChanged() {
        keyRejected = false
        failures = 0
        serverNotes = [:]
        storedNotes = [:]
        rebuildNotes()
        flush()
        if let video { loadNotes(video) }
    }
}

/// Jarvis's key for the notes, kept in the login Keychain rather than in preferences.
enum NotchVideoNotesKeychain {
    private static let service = (Bundle.main.bundleIdentifier ?? "com.vorssaint.utils") + ".video-notes"
    private static let account = "jarvis-api-key"

    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func read() -> String? {
        var lookup = query
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(lookup as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data, let key = String(data: data, encoding: .utf8), !key.isEmpty else { return nil }
        return key
    }

    static func save(_ key: String) -> Bool {
        let data = Data(key.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    static func delete() {
        SecItemDelete(query as CFDictionary)
    }
}
