// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Foundation
import os.log
import Security

/// Keeps the island's list and the tasks due today in Todoist the same, both
/// ways, through the Sync API and the user's API token. Each request carries
/// the changes made here and comes back with only what changed in Todoist
/// since the last, so it can ask often: every 15 seconds while the list is
/// on screen, every minute otherwise, and at once on opening the list, on
/// waking and before a reminder. Todoist has the last word, and the list is
/// rebuilt from what it says once every change made here has been sent.
final class NotchTodoistService: ObservableObject {
    static let shared = NotchTodoistService()

    enum Status: Equatable {
        case off, connecting, synced, offline, rejected
    }

    @Published private(set) var status: Status = .off
    @Published private(set) var connected = false
    /// The list is on screen, so Todoist is asked more often, and at once.
    var pageVisible = false {
        didSet {
            guard pageVisible != oldValue else { return }
            if pageVisible { syncNow() } else { reschedule() }
        }
    }

    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "vorssaint", category: "Todoist")
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        return URLSession(configuration: configuration)
    }()
    private let queueStore = NotchTodoistQueueStore(directoryURL: PrivateFileStore.containerURL)
    private var token: String?
    private var running = false
    private var syncToken = NotchTodoistSupport.fullSyncToken
    private var items: [String: NotchTodoistItem] = [:]
    private var userID: String?
    private var queue: [NotchTodoistCommand]
    private var request: URLSessionDataTask?
    private var sending = Set<String>()
    private var again = false
    private var waiters: [() -> Void] = []
    private var timer: DispatchSourceTimer?
    private var failures = 0
    private var retryAfter: TimeInterval?
    private var observers: [NSObjectProtocol] = []

    private init() {
        token = NotchTodoistKeychain.read()
        connected = token != nil
        queue = queueStore.load()
    }

    // MARK: - Lifecycle

    /// Runs while the island shows its list and a token is kept.
    func syncWithPreferences() {
        guard connected, NotchSupport.isEnabled(), NotchSupport.modules().contains(.tasks) else { stop(); return }
        guard !running else { return }
        running = true
        let workspace = NSWorkspace.shared.notificationCenter
        observers = [
            workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                self?.syncNow()
            },
            // At midnight yesterday's rows go, finished ones included, and
            // today's come in from what is already known.
            NotificationCenter.default.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main) { [weak self] _ in
                self?.rebuild()
                self?.syncNow()
            },
        ]
        syncNow()
    }

    func stop() {
        running = false
        timer?.cancel()
        timer = nil
        request?.cancel()
        request = nil
        sending = []
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0); NotificationCenter.default.removeObserver($0) }
        observers = []
        finishWaiters()
    }

    /// Keeps the token in the Keychain and reads everything once.
    func connect(_ token: String) {
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return }
        stop()
        if !NotchTodoistKeychain.save(token) { Self.log.error("todoist token could not be kept in the keychain") }
        self.token = token
        connected = true
        syncToken = NotchTodoistSupport.fullSyncToken
        items = [:]
        userID = nil
        failures = 0
        retryAfter = nil
        status = .connecting
        syncWithPreferences()
    }

    /// Forgets the token and what was waiting to be sent; Todoist's rows
    /// leave the list, and tasks written without it stay.
    func disconnect() {
        stop()
        NotchTodoistKeychain.delete()
        token = nil
        connected = false
        syncToken = NotchTodoistSupport.fullSyncToken
        items = [:]
        userID = nil
        queue = []
        queueStore.save(queue)
        status = .off
        NotchTaskService.shared.dropTodoist()
    }

    // MARK: - Changes made here

    func enqueue(_ command: NotchTodoistCommand?) {
        guard let command, connected else { return }
        queue.append(command)
        queueStore.save(queue)
        syncNow()
    }

    /// A task deleted here: one Todoist has not heard of yet is never sent.
    func delete(_ link: NotchTodoistLink) {
        if let next = NotchTodoistSupport.forgetting(link.id, in: queue, sending: sending) {
            queue = next
            queueStore.save(queue)
        } else {
            enqueue(NotchTodoistSupport.delete(link))
        }
    }

    /// Asks Todoist before a reminder goes out, so one finished elsewhere
    /// stays quiet; the reminder waits a few seconds at most.
    func refresh(then completion: @escaping () -> Void) {
        guard running, status != .rejected else { completion(); return }
        var called = false
        let once = {
            guard !called else { return }
            called = true
            completion()
        }
        syncNow(then: once)
        DispatchQueue.main.asyncAfter(deadline: .now() + NotchTodoistSupport.reminderWait, execute: once)
    }

    // MARK: - Sync

    func syncNow(then completion: (() -> Void)? = nil) {
        if let completion { waiters.append(completion) }
        guard running, let token, status != .rejected else { finishWaiters(); return }
        guard request == nil else { again = true; return }
        let commands = Array(queue.prefix(NotchTodoistSupport.maximumCommands))
        guard let body = NotchTodoistSupport.formBody(syncToken: syncToken, commands: commands) else {
            finishWaiters()
            return
        }
        timer?.cancel()
        timer = nil
        again = false
        sending = Set(commands.map(\.uuid))
        var urlRequest = URLRequest(url: NotchTodoistSupport.endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = body
        let task = session.dataTask(with: urlRequest) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.finish(data: data, response: response as? HTTPURLResponse, error: error, sent: commands, token: token)
            }
        }
        request = task
        task.resume()
    }

    private func finish(data: Data?, response: HTTPURLResponse?, error: Error?, sent: [NotchTodoistCommand], token: String) {
        request = nil
        sending = []
        // Disconnected, stopped or given another token while it was asked.
        guard running, token == self.token else { finishWaiters(); return }
        let code = response?.statusCode ?? 0
        if code == 401 || code == 403 {
            status = .rejected
            finishWaiters()
            return
        }
        guard code == 200, let data, let reply = try? JSONDecoder().decode(NotchTodoistResponse.self, from: data) else {
            if let error { Self.log.notice("todoist sync failed: \(error.localizedDescription, privacy: .public)") }
            failures += 1
            retryAfter = (response?.value(forHTTPHeaderField: "Retry-After")).flatMap(TimeInterval.init)
            status = .offline
            finishWaiters()
            reschedule()
            return
        }
        failures = 0
        retryAfter = nil
        status = .synced
        syncToken = reply.syncToken
        if let id = reply.userID { userID = id }
        items = NotchTodoistSupport.applying(reply, to: items)
        let finished = Set(sent.filter { reply.finished[$0.uuid] ?? true }.map(\.uuid))
        queue.removeAll { finished.contains($0.uuid) }
        for (temporary, real) in reply.tempIDs {
            queue = queue.map { $0.replacingID(temporary, with: real) }
            NotchTaskService.shared.replaceTodoistID(temporary, with: real)
        }
        queueStore.save(queue)
        // Changes made while this was out go at once; the list is rebuilt
        // from the answer to them, so it never shows them undone.
        let sentIDs = Set(sent.map(\.uuid))
        if again || queue.contains(where: { !sentIDs.contains($0.uuid) }) {
            syncNow()
            return
        }
        if queue.isEmpty { rebuild() }
        finishWaiters()
        reschedule()
    }

    private func rebuild() {
        guard connected, syncToken != NotchTodoistSupport.fullSyncToken else { return }
        NotchTaskService.shared.applyTodoist(items, userID: userID)
    }

    private func reschedule() {
        timer?.cancel()
        timer = nil
        guard running, request == nil, status != .rejected else { return }
        let delay = failures > 0
            ? NotchTodoistSupport.backoff(failures: failures, retryAfter: retryAfter)
            : pageVisible ? NotchTodoistSupport.pageInterval : NotchTodoistSupport.backgroundInterval
        let timer = DispatchSource.makeTimerSource(queue: .main)
        // A wall-clock deadline, so a Mac just awake asks at once.
        timer.schedule(wallDeadline: .now() + delay, leeway: .seconds(2))
        timer.setEventHandler { [weak self] in self?.syncNow() }
        timer.resume()
        self.timer = timer
    }

    private func finishWaiters() {
        let waiting = waiters
        waiters = []
        waiting.forEach { $0() }
    }
}

/// The API token, kept in the login Keychain rather than in preferences.
enum NotchTodoistKeychain {
    private static let service = (Bundle.main.bundleIdentifier ?? "com.vorssaint.utils") + ".todoist"
    private static let account = "api-token"

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
              let data = result as? Data, let token = String(data: data, encoding: .utf8), !token.isEmpty else { return nil }
        return token
    }

    static func save(_ token: String) -> Bool {
        let data = Data(token.utf8)
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
