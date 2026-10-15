// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import os.log
import UserNotifications

enum Notifier {
    static let whatsAppOrganizerUndoActionIdentifier =
        "com.vorssaint.notification.whatsapp-organizer.undo"
    private static let whatsAppOrganizerTransactionKey =
        "com.vorssaint.notification.whatsapp-organizer.transaction"
    private static let whatsAppOrganizerCategoryIdentifier =
        "com.vorssaint.notification.whatsapp-organizer"
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "vorssaint",
                                    category: "notifications")

    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            // A denied prompt is the user's call; a request that ERRORS means
            // notifications silently cannot work at all — leave a trace so
            // that state is diagnosable instead of invisible.
            if let error {
                log.error("notification authorization failed: \(error.localizedDescription, privacy: .public)")
            } else if !granted {
                log.notice("notification authorization not granted")
            }
        }
    }

    static func post(title: String, body: String) {
        post(title: title, body: body, categoryIdentifier: nil, userInfo: [:])
    }

    /// Hands macOS notifications to deliver at a time of day while the app
    /// is not running, and waits briefly so they are delivered to the
    /// notification center before a quit goes on.
    static func schedule(_ reminders: [(identifier: String, title: String, body: String, hour: Int, minute: Int)],
                         timeout: TimeInterval) {
        guard !reminders.isEmpty else { return }
        let center = UNUserNotificationCenter.current()
        let added = DispatchGroup()
        added.enter()
        center.getNotificationSettings { settings in
            defer { added.leave() }
            guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional else { return }
            for reminder in reminders {
                let content = UNMutableNotificationContent()
                content.title = reminder.title
                content.body = reminder.body
                content.sound = .default
                let trigger = UNCalendarNotificationTrigger(
                    dateMatching: DateComponents(hour: reminder.hour, minute: reminder.minute), repeats: false)
                added.enter()
                center.add(UNNotificationRequest(identifier: reminder.identifier, content: content, trigger: trigger)) { error in
                    if let error {
                        log.error("notification scheduling failed: \(error.localizedDescription, privacy: .public)")
                    }
                    added.leave()
                }
            }
        }
        _ = added.wait(timeout: .now() + timeout)
    }

    static func removePending(withPrefix prefix: String) {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            let identifiers = requests.map(\.identifier).filter { $0.hasPrefix(prefix) }
            if !identifiers.isEmpty { center.removePendingNotificationRequests(withIdentifiers: identifiers) }
        }
    }

    static func postWhatsAppOrganization(title: String,
                                         body: String,
                                         undoTitle: String,
                                         transactionID: UUID) {
        let center = UNUserNotificationCenter.current()
        let undo = UNNotificationAction(
            identifier: whatsAppOrganizerUndoActionIdentifier,
            title: undoTitle,
            options: [.foreground])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: whatsAppOrganizerCategoryIdentifier,
                                   actions: [undo], intentIdentifiers: [], options: []),
        ])
        post(title: title, body: body,
             categoryIdentifier: whatsAppOrganizerCategoryIdentifier,
             userInfo: [whatsAppOrganizerTransactionKey: transactionID.uuidString])
    }

    static func whatsAppOrganizerTransactionID(from response: UNNotificationResponse) -> UUID? {
        guard response.actionIdentifier == whatsAppOrganizerUndoActionIdentifier,
              let raw = response.notification.request.content.userInfo[
                whatsAppOrganizerTransactionKey] as? String else { return nil }
        return UUID(uuidString: raw)
    }

    private static func post(title: String,
                             body: String,
                             categoryIdentifier: String?,
                             userInfo: [AnyHashable: Any]) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional else {
                log.notice("notification dropped: authorization status \(settings.authorizationStatus.rawValue)")
                return
            }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            if let categoryIdentifier { content.categoryIdentifier = categoryIdentifier }
            content.userInfo = userInfo
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            center.add(request) { error in
                if let error {
                    log.error("notification delivery failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }
}
