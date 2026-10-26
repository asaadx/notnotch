// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Video Notes: telling the playing video's tab by its title, reading video
/// ids from every YouTube address, the times on the pills, Safari's replies,
/// the requests Jarvis gets and the queue that retries them.
enum NotchVideoNotesTests {
    static func run(_ suite: TestSuite) {
        videoIDs(suite)
        titles(suite)
        times(suite)
        safari(suite)
        requests(suite)
        queue(suite)
        strings(suite)
    }

    private static func videoIDs(_ suite: TestSuite) {
        let id = "dQw4w9WgXcQ"
        for address in ["https://www.youtube.com/watch?v=\(id)", "https://youtube.com/watch?v=\(id)&t=42s",
                        "https://m.youtube.com/watch?feature=share&v=\(id)", "https://music.youtube.com/watch?v=\(id)",
                        "https://youtu.be/\(id)?si=abc", "https://www.youtube.com/shorts/\(id)",
                        "https://www.youtube.com/embed/\(id)", "https://www.youtube.com/live/\(id)",
                        "  http://www.youtube.com/watch?v=\(id)  "] {
            suite.expect(NotchVideoNotesSupport.videoID(from: address) == id, "\(address) is video \(id)")
        }
        for address in ["https://www.youtube.com/", "https://www.youtube.com/watch?v=short", "https://www.youtube.com/@channel",
                        "https://vimeo.com/123456789", "ftp://youtu.be/\(id)", "https://notyoutube.com/watch?v=\(id)",
                        "https://www.youtube.com/watch?v=\(id)x", "not an address", ""] {
            suite.expect(NotchVideoNotesSupport.videoID(from: address) == nil, "\(address) is no video")
        }
        suite.expect(NotchVideoNotesSupport.canonicalURL(videoID: id) == "https://www.youtube.com/watch?v=\(id)",
                     "a video's address is its watch page, as Jarvis keeps it")
        suite.expect(NotchVideoNotesSupport.thumbnailURL(videoID: id)?.absoluteString == "https://i.ytimg.com/vi/\(id)/hqdefault.jpg",
                     "the thumbnail is YouTube's hqdefault still")
        suite.expect(NotchVideoNotesSupport.seekURL(videoID: id, seconds: 95.8) == "https://www.youtube.com/watch?v=\(id)&t=95s",
                     "a reload starts at the whole second")
        suite.expect(NotchVideoNotesSupport.seekURL(videoID: id, seconds: -3) == "https://www.youtube.com/watch?v=\(id)&t=0s",
                     "a reload never starts before the beginning")
    }

    private static func titles(_ suite: TestSuite) {
        suite.expect(NotchVideoNotesSupport.videoTitle(fromTabName: "How to Speak - YouTube") == "How to Speak",
                     "YouTube's suffix goes")
        suite.expect(NotchVideoNotesSupport.videoTitle(fromTabName: "(12) How to Speak - YouTube") == "How to Speak",
                     "the unread count before the title goes")
        suite.expect(NotchVideoNotesSupport.videoTitle(fromTabName: "Talk - YouTube - YouTube") == "Talk - YouTube",
                     "only one suffix goes")
        suite.expect(NotchVideoNotesSupport.videoTitle(fromTabName: "(Live) Q&A") == "(Live) Q&A",
                     "brackets that are not a count stay")
        suite.expect(NotchVideoNotesSupport.sameTitle("How  to speak", "How to Speak - YouTube"), "titles compare as words")
        suite.expect(!NotchVideoNotesSupport.sameTitle("How to Speak", "How to Listen"), "different titles differ")
        suite.expect(!NotchVideoNotesSupport.sameTitle(nil, "How to Speak") && !NotchVideoNotesSupport.sameTitle("", ""),
                     "no title matches nothing")

        let speak = NotchSafariTab(windowID: 7, index: 1, name: "How to Speak - YouTube", url: "https://www.youtube.com/watch?v=Unzc731iCUY")
        let art = NotchSafariTab(windowID: 7, index: 2, name: "(3) The Art of Code - YouTube", url: "https://youtu.be/6avJHaC3C2U")
        let mail = NotchSafariTab(windowID: 9, index: 1, name: "How to Speak", url: "https://mail.example.com/")
        let home = NotchSafariTab(windowID: 9, index: 2, name: "YouTube", url: "https://www.youtube.com/")
        let tabs = [mail, home, speak, art]
        suite.expect(NotchVideoNotesSupport.matchingTab(nowPlayingTitle: "The Art of Code", in: tabs) == art,
                     "Now Playing's title picks its tab")
        suite.expect(NotchVideoNotesSupport.matchingTab(nowPlayingTitle: "How to Speak", in: tabs) == speak,
                     "a page that is not a video never matches, even with the same title")
        suite.expect(NotchVideoNotesSupport.matchingTab(nowPlayingTitle: "Something else", in: tabs) == nil,
                     "with two videos and no title match, none is guessed")
        suite.expect(NotchVideoNotesSupport.matchingTab(nowPlayingTitle: nil, in: [mail, speak]) == speak,
                     "a single video tab is the one")
        suite.expect(NotchVideoNotesSupport.selectedTab(in: tabs, pinnedVideoID: "6avJHaC3C2U", nowPlayingTitle: "How to Speak") == art,
                     "a video picked by hand wins over Now Playing")
        suite.expect(NotchVideoNotesSupport.selectedTab(in: tabs, pinnedVideoID: "aaaaaaaaaaa", nowPlayingTitle: "How to Speak") == speak,
                     "a picked video that closed gives way to Now Playing")
        let again = NotchSafariTab(windowID: 9, index: 3, name: "How to Speak - YouTube", url: "https://youtu.be/Unzc731iCUY")
        suite.expect(NotchVideoNotesSupport.videoTabs(tabs + [again]) == [speak, art],
                     "the picker lists each video once, in Safari's order")
    }

    private static func times(_ suite: TestSuite) {
        suite.expect(NotchVideoNotesSupport.timeLabel(0) == "0:00", "the start reads 0:00")
        suite.expect(NotchVideoNotesSupport.timeLabel(132.9) == "2:12", "seconds are whole, never rounded up")
        suite.expect(NotchVideoNotesSupport.timeLabel(3599) == "59:59", "under an hour is m:ss")
        suite.expect(NotchVideoNotesSupport.timeLabel(3723) == "1:02:03", "an hour on is h:mm:ss")
        suite.expect(NotchVideoNotesSupport.timeLabel(-5) == "0:00" && NotchVideoNotesSupport.timeLabel(.nan) == "0:00",
                     "nothing reads before the start")
        suite.expectClose(NotchVideoNotesSupport.fraction(30, duration: 120), 0.25, "a mark sits at its share of the video")
        suite.expect(NotchVideoNotesSupport.fraction(500, duration: 120) == 1 && NotchVideoNotesSupport.fraction(5, duration: 0) == 0,
                     "marks stay on the bar")

        let start = Date(timeIntervalSince1970: 1000)
        let playing = NotchVideoState(time: 10, duration: 60, paused: false, channel: nil, sampledAt: start)
        suite.expectClose(playing.position(at: start.addingTimeInterval(5)), 15, "a playing video moves on")
        suite.expectClose(playing.position(at: start.addingTimeInterval(500)), 60, "and stops at its end")
        var paused = playing
        paused.paused = true
        suite.expectClose(paused.position(at: start.addingTimeInterval(5)), 10, "a paused one stays put")
    }

    private static func safari(_ suite: TestSuite) {
        let output = "41\u{1F}1\u{1F}How to Speak - YouTube\u{1F}https://www.youtube.com/watch?v=Unzc731iCUY\u{1E}"
            + "41\u{1F}2\u{1F}\u{1F}\u{1E}"
            + "88\u{1F}1\u{1F}A title\u{1F}with a tab\u{1F}https://example.com/\u{1E}"
            + "bad record\u{1E}"
        let tabs = NotchVideoNotesSupport.parseTabs(output)
        suite.expect(tabs.count == 3, "every whole record reads, a broken one is left out")
        suite.expect(tabs.first == NotchSafariTab(windowID: 41, index: 1, name: "How to Speak - YouTube",
                                                  url: "https://www.youtube.com/watch?v=Unzc731iCUY"),
                     "a tab keeps its window, place, title and address")
        suite.expect(tabs.count == 3 && tabs[1].name.isEmpty && tabs[1].url.isEmpty, "an empty tab reads as empty")
        suite.expect(tabs.count == 3 && tabs[2].name == "A title" && tabs[2].url == "with a tab\u{1F}https://example.com/",
                     "a stray separator stays inside the last field")
        suite.expect(NotchVideoNotesSupport.parseTabs("").isEmpty, "no windows is no tabs")

        let now = Date()
        let state = NotchVideoNotesSupport.parseState("132.5\u{1F}3823.4\u{1F}0\u{1F} MIT OpenCourseWare ", at: now)
        suite.expect(state == NotchVideoState(time: 132.5, duration: 3823.4, paused: false, channel: "MIT OpenCourseWare", sampledAt: now),
                     "the player's time, length, state and channel read")
        suite.expect(NotchVideoNotesSupport.parseState("12\u{1F}NaN\u{1F}1\u{1F}", at: now)
                        == NotchVideoState(time: 12, duration: 0, paused: true, channel: nil, sampledAt: now),
                     "a live stream with no length still has a time")
        suite.expect(NotchVideoNotesSupport.parseState("", at: now) == nil, "a page with no video has no state")

        let tab = NotchSafariTab(windowID: 41, index: 2, name: "", url: "")
        let script = NotchVideoNotesSupport.javaScriptScript("a\"b\\c", in: tab)
        suite.expect(script.hasSuffix("do JavaScript \"a\\\"b\\\\c\" in tab 2 of window id 41"),
                     "JavaScript reaches one tab of one window, quoted for AppleScript")
        suite.expect(NotchVideoNotesSupport.seekJavaScript(95).contains("v.currentTime=95.000"), "a seek sets the player's time")
        suite.expect(NotchVideoNotesSupport.openScript("https://youtu.be/x", in: tab).hasSuffix("tab 2 of window id 41 to \"https://youtu.be/x\""),
                     "a reload opens the address in the same tab")
        suite.expect(NotchVideoNotesSupport.tabsScript.contains("application id \"com.apple.Safari\""),
                     "Safari is addressed by its bundle")
    }

    private static func requests(_ suite: TestSuite) {
        suite.expect(NotchVideoNotesSupport.baseURL(from: " https://jvrvis.vercel.app/ ")?.absoluteString == "https://jvrvis.vercel.app",
                     "Jarvis's address loses its trailing slash")
        suite.expect(NotchVideoNotesSupport.baseURL(from: "http://localhost:3103")?.absoluteString == "http://localhost:3103",
                     "a local Jarvis works")
        suite.expect(NotchVideoNotesSupport.baseURL(from: "jvrvis.vercel.app") == nil
                        && NotchVideoNotesSupport.baseURL(from: "ftp://x.y") == nil,
                     "only http(s) addresses are taken")

        let note = NotchVideoNotesPending(clientId: "6f1c2c1e-4c3e-4a43-9a52-0b8d1d0f2a11",
                                          url: "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
                                          title: String(repeating: "t", count: 400), channel: "Rick Astley",
                                          t: 95, text: "  the key idea\n", createdAt: Date())
        let base = NotchVideoNotesSupport.baseURL(from: "http://localhost:3103")!
        let request = NotchVideoNotesSupport.postRequest(baseURL: base, key: "secret", note: note)
        suite.expect(request?.url?.absoluteString == "http://localhost:3103/api/learning/notes" && request?.httpMethod == "POST",
                     "notes are posted to Jarvis's notes route")
        suite.expect(request?.value(forHTTPHeaderField: "Authorization") == "Bearer secret", "with the key as a bearer token")
        let body = request?.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        suite.expect(body?["text"] as? String == "  the key idea\n", "the note goes exactly as typed")
        suite.expect(body?["t"] as? Int == 95 && body?["clientId"] as? String == note.clientId
                        && body?["channel"] as? String == "Rick Astley", "with its second, client id and channel")
        suite.expect((body?["title"] as? String)?.count == NotchVideoNotesSupport.maximumTitleLength,
                     "a title longer than Jarvis keeps is cut to fit")
        let anonymous = NotchVideoNotesPending(clientId: "abcdefgh", url: note.url, title: "x", channel: nil, t: 0, text: "y", createdAt: Date())
        suite.expect(NotchVideoNotesSupport.requestBody(anonymous).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }?["channel"] == nil,
                     "no channel is not sent")

        let list = NotchVideoNotesSupport.notesRequest(baseURL: base, key: "secret", videoURL: note.url)
        suite.expect(list?.url?.absoluteString == "http://localhost:3103/api/learning/notes?url=https%3A%2F%2Fwww.youtube.com%2Fwatch%3Fv%3DdQw4w9WgXcQ",
                     "a video's notes are asked for by its address: \(list?.url?.absoluteString ?? "none")")

        let stored = Data(#"{"ok":true,"source":{},"note":{"id":"n1","sourceId":"s1","t":95,"text":"the key idea","createdAt":"2026-10-26T12:00:00.000Z"}}"#.utf8)
        suite.expect(NotchVideoNotesSupport.outcome(status: 201, data: stored)
                        == .stored(NotchVideoNote(id: "n1", t: 95, text: "the key idea",
                                                  createdAt: NotchVideoNotesSupport.parseDate("2026-10-26T12:00:00Z"))),
                     "a new note is stored")
        suite.expect(NotchVideoNotesSupport.outcome(status: 200, data: stored) != .failed, "a retry of a stored note is stored")
        suite.expect(NotchVideoNotesSupport.outcome(status: 401, data: nil) == .rejectedKey
                        && NotchVideoNotesSupport.outcome(status: 403, data: nil) == .rejectedKey, "a refused key is said so")
        for status in [nil, 400, 500, 503] as [Int?] {
            suite.expect(NotchVideoNotesSupport.outcome(status: status, data: nil) == .failed, "\(String(describing: status)) is tried again")
        }
        let listed = Data(#"{"ok":true,"source":null,"notes":[{"id":"a","sourceId":"s","t":5,"text":"one","createdAt":"2026-10-26T12:00:00Z"}]}"#.utf8)
        suite.expect(NotchVideoNotesSupport.notes(fromListReply: listed)?.map(\.id) == ["a"], "a video's notes read")
        suite.expect(NotchVideoNotesSupport.notes(fromListReply: Data("{}".utf8)) == nil, "a reply that is not a list is ignored")
    }

    private static func queue(_ suite: TestSuite) {
        let url = "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
        let first = NotchVideoNotesPending(clientId: "client-1", url: url, title: "T", channel: nil, t: 30, text: "first",
                                           createdAt: Date(timeIntervalSince1970: 1))
        let second = NotchVideoNotesPending(clientId: "client-2", url: url, title: "T", channel: nil, t: 10, text: "second",
                                            createdAt: Date(timeIntervalSince1970: 2))
        let other = NotchVideoNotesPending(clientId: "client-3", url: "https://www.youtube.com/watch?v=Unzc731iCUY",
                                           title: "U", channel: nil, t: 1, text: "other", createdAt: Date(timeIntervalSince1970: 3))
        let waiting = [first, second, other]

        let failed = NotchVideoNotesSupport.queue(waiting, after: .failed, for: first.clientId)
        suite.expect(failed == waiting, "a failed send keeps the note, its place and its client id")
        suite.expect(NotchVideoNotesSupport.requestBody(failed[0]) == NotchVideoNotesSupport.requestBody(first),
                     "a retry sends exactly the same body")
        suite.expect(NotchVideoNotesSupport.queue(waiting, after: .rejectedKey, for: first.clientId) == waiting,
                     "a refused key keeps every note for the next key")
        suite.expect(NotchVideoNotesSupport.queue(waiting, after: .stored(nil), for: first.clientId) == [second, other],
                     "a stored note leaves the queue")

        suite.expect(NotchVideoNotesSupport.backoff(failures: 0) == 0, "nothing waits before a failure")
        suite.expect(NotchVideoNotesSupport.backoff(failures: 1) == 5 && NotchVideoNotesSupport.backoff(failures: 2) == 10,
                     "each failure waits twice as long")
        suite.expect(NotchVideoNotesSupport.backoff(failures: 40) == 300, "never more than five minutes")

        let server = [NotchVideoNote(id: "s1", t: 20, text: "from Jarvis", createdAt: nil)]
        let justStored = [NotchVideoNote(id: "s2", t: 40, text: "just sent", createdAt: nil),
                          NotchVideoNote(id: "s1", t: 20, text: "from Jarvis", createdAt: nil)]
        let shown = NotchVideoNotesSupport.displayNotes(server: server, stored: justStored, queue: waiting, videoURL: url)
        suite.expect(shown.map(\.id) == ["client-2", "s1", "client-1", "s2"],
                     "the list holds Jarvis's notes, the ones just stored and the waiting ones, in the video's order, once each")
        suite.expect(shown.filter(\.pending).map(\.id) == ["client-2", "client-1"], "only queued notes read as waiting")

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("notch-video-notes-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = NotchVideoNotesQueueStore(directoryURL: root)
        suite.expect(store.load().isEmpty, "no file is an empty queue")
        suite.expect(store.save(waiting), "the queue saves")
        suite.expect(NotchVideoNotesQueueStore(directoryURL: root).load() == waiting,
                     "waiting notes come back after a restart with their client ids")
        try? Data("not json".utf8).write(to: root.appendingPathComponent(NotchVideoNotesSupport.queueFileName))
        suite.expect(store.load().isEmpty, "an unreadable queue reads as empty")
    }

    private static func strings(_ suite: TestSuite) {
        for language in AppLanguage.allCases {
            let text = FeatureStrings.notchVideoNotes(language)
            suite.expect(!text.title.isEmpty && text.playFrom("1:00").contains("1:00")
                            && text.count(3, agreement: language.countAgreement).contains("3"),
                         "\(language.rawValue) names the page and fills its formats")
        }
        let english = FeatureStrings.notchVideoNotes(.enUS)
        suite.expect(english.title == "Video Notes", "the page is called Video Notes")
        suite.expect(english.count(1, agreement: .oneAndMany) == "1 note" && english.count(4, agreement: .oneAndMany) == "4 notes",
                     "one note, many notes")
        let russian = FeatureStrings.notchVideoNotes(.ru)
        suite.expect(russian.count(21, agreement: .byLastDigits) == "21 заметка"
                        && russian.count(3, agreement: .byLastDigits) == "3 заметки"
                        && russian.count(12, agreement: .byLastDigits) == "12 заметок",
                     "Russian agrees the noun with the last digits")
        let slovak = FeatureStrings.notchVideoNotes(.sk)
        suite.expect(slovak.count(22, agreement: .byWholeNumber) == "22 poznámok"
                        && slovak.count(2, agreement: .byWholeNumber) == "2 poznámky",
                     "Slovak agrees the noun with the whole number")
    }
}
