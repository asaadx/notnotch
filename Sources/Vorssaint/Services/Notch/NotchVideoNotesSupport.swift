// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// One Safari tab as Apple Events report it: the window it is in, its place
/// there (from one), and what its title bar and address read.
struct NotchSafariTab: Equatable, Hashable {
    let windowID: Int
    let index: Int
    let name: String
    let url: String

    var videoID: String? { NotchVideoNotesSupport.videoID(from: url) }
    /// The title the video page gives itself, without YouTube's own suffix.
    var videoTitle: String { NotchVideoNotesSupport.videoTitle(fromTabName: name) }
}

/// What the page's video element says, read through `do JavaScript`.
struct NotchVideoState: Equatable {
    var time: Double
    var duration: Double
    var paused: Bool
    var channel: String?
    var sampledAt: Date

    func position(at date: Date) -> Double {
        let moved = paused ? 0 : max(0, date.timeIntervalSince(sampledAt))
        let position = time + moved
        return duration > 0 ? min(duration, max(0, position)) : max(0, position)
    }
}

/// A note as the page lists it. One still waiting to reach Jarvis carries
/// its client id as its id until Jarvis gives it one of its own.
struct NotchVideoNote: Equatable, Identifiable {
    let id: String
    let t: Int
    let text: String
    let createdAt: Date?
    var pending = false
}

/// A note written here and not yet stored by Jarvis. It keeps everything
/// its request needs, so a retry sends exactly the same body again.
struct NotchVideoNotesPending: Codable, Equatable {
    let clientId: String
    let url: String
    let title: String
    let channel: String?
    let t: Int
    let text: String
    let createdAt: Date
}

/// How one attempt to store a note ended.
enum NotchVideoNotesOutcome: Equatable {
    /// Jarvis has it: newly (201) or from an earlier try with this client id (200).
    case stored(NotchVideoNote?)
    /// The key was refused; nothing will be stored until it changes.
    case rejectedKey
    /// Anything else; the note stays queued and is tried again later.
    case failed
}

enum NotchVideoNotesSupport {
    static let defaultBaseURL = "https://jvrvis.vercel.app"
    static let endpointPath = "api/learning/notes"
    static let queueFileName = "VideoNotesQueue.json"
    /// Jarvis's own limits, so a note it would refuse is never queued.
    static let maximumTextLength = 2000
    static let maximumTitleLength = 300
    static let maximumChannelLength = 200
    static let maximumQueued = 500
    /// A seek through YouTube's own address is the slowest path; one this
    /// close to the current time is not worth reloading the page for.
    static let seekTolerance: Double = 1

    // MARK: - Addresses

    private static let youtubeHosts: Set<String> = ["youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com"]

    /// The eleven-character id of a YouTube video, from any of the address
    /// forms Jarvis accepts as the same video: watch, youtu.be, shorts,
    /// embed and live.
    static func videoID(from address: String) -> String? {
        guard let components = URLComponents(string: address.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = components.host?.lowercased() else { return nil }
        let parts = components.path.split(separator: "/", omittingEmptySubsequences: false).dropFirst().map(String.init)
        var id: String?
        if host == "youtu.be" || host == "www.youtu.be" {
            id = parts.first
        } else if youtubeHosts.contains(host) {
            switch parts.first {
            case "watch": id = components.queryItems?.first(where: { $0.name == "v" })?.value
            case "shorts", "embed", "live": id = parts.count > 1 ? parts[1] : nil
            default: id = nil
            }
        }
        guard let id, isVideoID(id) else { return nil }
        return id
    }

    static func isVideoID(_ value: String) -> Bool {
        value.count == 11 && value.unicodeScalars.allSatisfy {
            ("a"..."z").contains($0) || ("A"..."Z").contains($0) || ("0"..."9").contains($0) || $0 == "_" || $0 == "-"
        }
    }

    static func canonicalURL(videoID: String) -> String {
        "https://www.youtube.com/watch?v=\(videoID)"
    }

    static func thumbnailURL(videoID: String) -> URL? {
        URL(string: "https://i.ytimg.com/vi/\(videoID)/hqdefault.jpg")
    }

    /// The video's address that starts it at a whole second, for a Safari
    /// that will not run JavaScript sent to it.
    static func seekURL(videoID: String, seconds: Double) -> String {
        "\(canonicalURL(videoID: videoID))&t=\(Int(max(0, seconds.isFinite ? seconds : 0)))s"
    }

    /// Jarvis's address as typed in Settings, or nil if it is not an http(s) one.
    static func baseURL(from text: String) -> URL? {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https", let host = url.host, !host.isEmpty else { return nil }
        return url
    }

    static func endpoint(baseURL: URL) -> URL {
        baseURL.appendingPathComponent(endpointPath)
    }

    // MARK: - Titles

    /// "(3) How to Speak - YouTube" reads "How to Speak": the unread count
    /// YouTube puts first and its name after go.
    static func videoTitle(fromTabName name: String) -> String {
        var title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let count = title.range(of: #"^\(\d+\+?\)\s+"#, options: .regularExpression) {
            title.removeSubrange(count)
        }
        for suffix in [" - YouTube Music", " - YouTube", " – YouTube", " — YouTube"] where title.hasSuffix(suffix) {
            title.removeLast(suffix.count)
            break
        }
        return title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Titles compare as words: case, runs of spaces and YouTube's dressing aside.
    static func sameTitle(_ first: String?, _ second: String?) -> Bool {
        guard let first, let second else { return false }
        let a = comparable(first), b = comparable(second)
        return !a.isEmpty && a == b
    }

    private static func comparable(_ title: String) -> String {
        videoTitle(fromTabName: title)
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
            .folding(options: [.caseInsensitive, .widthInsensitive], locale: nil)
    }

    /// The YouTube video tab Now Playing is reading, by its title. With no
    /// title to go by, a single video tab can only be that one.
    static func matchingTab(nowPlayingTitle: String?, in tabs: [NotchSafariTab]) -> NotchSafariTab? {
        let videos = tabs.filter { $0.videoID != nil }
        if let title = nowPlayingTitle, let match = videos.first(where: { sameTitle($0.videoTitle, title) }) {
            return match
        }
        return videos.count == 1 ? videos[0] : nil
    }

    /// The tab the notes are for: the one picked by hand while its video is
    /// still open, otherwise the one Now Playing points at.
    static func selectedTab(in tabs: [NotchSafariTab], pinnedVideoID: String?, nowPlayingTitle: String?) -> NotchSafariTab? {
        if let pinnedVideoID, let pinned = tabs.first(where: { $0.videoID == pinnedVideoID }) { return pinned }
        return matchingTab(nowPlayingTitle: nowPlayingTitle, in: tabs)
    }

    /// Each YouTube video once, in Safari's order.
    static func videoTabs(_ tabs: [NotchSafariTab]) -> [NotchSafariTab] {
        var seen = Set<String>()
        return tabs.filter { tab in
            guard let id = tab.videoID else { return false }
            return seen.insert(id).inserted
        }
    }

    // MARK: - Time

    /// m:ss, or h:mm:ss from an hour on.
    static func timeLabel(_ interval: Double) -> String {
        let seconds = Int(min(604_800, max(0, interval.isFinite ? interval : 0)))
        return seconds >= 3600
            ? String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
            : String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    /// Where a note at `t` sits along a bar, from 0 to 1.
    static func fraction(_ t: Double, duration: Double) -> Double {
        guard duration > 0, t.isFinite else { return 0 }
        return min(1, max(0, t / duration))
    }

    // MARK: - Safari

    static let fieldSeparator: Character = "\u{1F}"
    static let recordSeparator: Character = "\u{1E}"

    /// Lists every tab two events a window at a time, since asking tab by
    /// tab costs one round trip each. Fields and records are split with the
    /// ASCII unit and record separators, which no title or address carries.
    static let tabsScript = """
    tell application id "com.apple.Safari"
        set fs to character id 31
        set rs to character id 30
        set out to ""
        repeat with w in windows
            try
                set wid to id of w
                set ns to name of every tab of w
                set us to URL of every tab of w
                repeat with i from 1 to count of ns
                    set n to item i of ns
                    if n is missing value then set n to ""
                    set u to item i of us
                    if u is missing value then set u to ""
                    set out to out & wid & fs & i & fs & n & fs & u & rs
                end repeat
            end try
        end repeat
        return out
    end tell
    """

    static func parseTabs(_ output: String) -> [NotchSafariTab] {
        output.split(separator: recordSeparator).compactMap { record in
            let fields = record.split(separator: fieldSeparator, maxSplits: 3, omittingEmptySubsequences: false)
            guard fields.count == 4, let window = Int(fields[0]), let index = Int(fields[1]), index > 0 else { return nil }
            return NotchSafariTab(windowID: window, index: index, name: String(fields[2]), url: String(fields[3]))
        }
    }

    /// The page's main video, its time, length, whether it is paused and
    /// the channel's name under it.
    static let stateJavaScript = """
    (function(){var v=document.querySelector('video.html5-main-video')||document.querySelector('video');\
    if(!v)return '';var c=document.querySelector('#owner #channel-name a')||document.querySelector('ytd-channel-name a');\
    return [v.currentTime,v.duration,v.paused?1:0,(c&&c.textContent||'').trim()].join('\\u001f');})()
    """

    static func seekJavaScript(_ seconds: Double) -> String {
        let value = max(0, seconds.isFinite ? seconds : 0)
        return "(function(){var v=document.querySelector('video.html5-main-video')||document.querySelector('video');"
            + "if(!v)return '';v.currentTime=\(String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), value));return 'ok';})()"
    }

    static let toggleJavaScript = """
    (function(){var v=document.querySelector('video.html5-main-video')||document.querySelector('video');\
    if(!v)return '';if(v.paused){v.play();}else{v.pause();}return 'ok';})()
    """

    static func parseState(_ output: String, at date: Date) -> NotchVideoState? {
        let fields = output.split(separator: fieldSeparator, omittingEmptySubsequences: false).map(String.init)
        guard fields.count >= 3, let time = Double(fields[0]), time.isFinite, time >= 0 else { return nil }
        let duration = Double(fields[1]).flatMap { $0.isFinite && $0 > 0 ? $0 : nil } ?? 0
        let channel = fields.count > 3 ? fields[3].trimmingCharacters(in: .whitespacesAndNewlines) : ""
        return NotchVideoState(time: time, duration: duration, paused: fields[2] == "1",
                               channel: channel.isEmpty ? nil : channel, sampledAt: date)
    }

    /// One tab of one window, addressed by the window's id so a window
    /// brought forward meanwhile cannot shift it.
    static func javaScriptScript(_ javaScript: String, in tab: NotchSafariTab) -> String {
        "tell application id \"com.apple.Safari\" to do JavaScript \(appleScriptLiteral(javaScript))"
            + " in tab \(tab.index) of window id \(tab.windowID)"
    }

    static func openScript(_ url: String, in tab: NotchSafariTab) -> String {
        "tell application id \"com.apple.Safari\" to set URL of tab \(tab.index) of window id \(tab.windowID)"
            + " to \(appleScriptLiteral(url))"
    }

    /// Brings the tab forward in its window, and the window and Safari forward.
    static func showScript(_ tab: NotchSafariTab) -> String {
        """
        tell application id "com.apple.Safari"
            set w to window id \(tab.windowID)
            set current tab of w to tab \(tab.index) of w
            set index of w to 1
            activate
        end tell
        """
    }

    static func appleScriptLiteral(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    // MARK: - Jarvis

    /// The body Jarvis expects. The text goes as typed; only the title and
    /// channel, which come from the page, are cut to Jarvis's limits.
    static func requestBody(_ note: NotchVideoNotesPending) -> Data? {
        var body: [String: Any] = [
            "url": note.url,
            "title": String(note.title.prefix(maximumTitleLength)),
            "t": note.t,
            "text": note.text,
            "clientId": note.clientId,
        ]
        if let channel = note.channel, !channel.isEmpty { body["channel"] = String(channel.prefix(maximumChannelLength)) }
        return try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
    }

    static func postRequest(baseURL: URL, key: String, note: NotchVideoNotesPending) -> URLRequest? {
        guard let body = requestBody(note) else { return nil }
        var request = URLRequest(url: endpoint(baseURL: baseURL))
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        return request
    }

    static func notesRequest(baseURL: URL, key: String, videoURL: String) -> URLRequest? {
        guard var components = URLComponents(url: endpoint(baseURL: baseURL), resolvingAgainstBaseURL: false) else { return nil }
        // Every reserved character of the address is escaped, so its own
        // query cannot leak into this one.
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        guard let value = videoURL.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        components.percentEncodedQuery = "url=" + value
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        return request
    }

    private struct NoteReply: Decodable {
        let id: String
        let t: Int
        let text: String
        let createdAt: String?
    }

    private struct PostReply: Decodable {
        let ok: Bool
        let note: NoteReply?
    }

    private struct ListReply: Decodable {
        let ok: Bool
        let notes: [NoteReply]
    }

    private static func note(_ reply: NoteReply) -> NotchVideoNote {
        NotchVideoNote(id: reply.id, t: reply.t, text: reply.text, createdAt: reply.createdAt.flatMap(parseDate))
    }

    static func parseDate(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }

    static func outcome(status: Int?, data: Data?) -> NotchVideoNotesOutcome {
        switch status {
        case 200, 201:
            let reply = data.flatMap { try? JSONDecoder().decode(PostReply.self, from: $0) }
            return .stored(reply?.note.map(note))
        case 401, 403: return .rejectedKey
        default: return .failed
        }
    }

    static func notes(fromListReply data: Data) -> [NotchVideoNote]? {
        guard let reply = try? JSONDecoder().decode(ListReply.self, from: data), reply.ok else { return nil }
        return reply.notes.map(note)
    }

    // MARK: - Queue

    /// Waits between retries: 5 seconds after the first failure, doubling
    /// to at most five minutes.
    static func backoff(failures: Int) -> TimeInterval {
        guard failures > 0 else { return 0 }
        return min(300, 5 * pow(2, Double(min(failures, 10) - 1)))
    }

    /// A stored note leaves the queue; a failed one keeps its place and its
    /// client id for the next try.
    static func queue(_ queue: [NotchVideoNotesPending], after outcome: NotchVideoNotesOutcome,
                      for clientId: String) -> [NotchVideoNotesPending] {
        guard case .stored = outcome else { return queue }
        return queue.filter { $0.clientId != clientId }
    }

    /// What the page lists for one video: what Jarvis holds, what it took
    /// since, and what is still waiting, in the video's order.
    static func displayNotes(server: [NotchVideoNote], stored: [NotchVideoNote],
                             queue: [NotchVideoNotesPending], videoURL: String) -> [NotchVideoNote] {
        var seen = Set<String>()
        var notes = (server + stored).filter { seen.insert($0.id).inserted }
        notes += queue.filter { $0.url == videoURL && !seen.contains($0.clientId) }.map {
            NotchVideoNote(id: $0.clientId, t: $0.t, text: $0.text, createdAt: $0.createdAt, pending: true)
        }
        return notes.enumerated().sorted { lhs, rhs in
            if lhs.element.t != rhs.element.t { return lhs.element.t < rhs.element.t }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }

    static func isBlank(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// The notes still waiting for Jarvis, beside the app's other private
/// files, so a quit or a crash never loses one.
struct NotchVideoNotesQueueStore {
    let directoryURL: URL?

    func load() -> [NotchVideoNotesPending] {
        guard let directoryURL,
              let data = try? Data(contentsOf: directoryURL.appendingPathComponent(NotchVideoNotesSupport.queueFileName))
        else { return [] }
        return (try? Self.decoder.decode([NotchVideoNotesPending].self, from: data)) ?? []
    }

    @discardableResult
    func save(_ queue: [NotchVideoNotesPending]) -> Bool {
        guard let directoryURL, let data = try? Self.encoder.encode(queue) else { return false }
        return PrivateFileStore.createDirectory(at: directoryURL)
            && PrivateFileStore.write(data, to: directoryURL.appendingPathComponent(NotchVideoNotesSupport.queueFileName))
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
