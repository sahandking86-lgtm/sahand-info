//
//  ReminderNotifications.swift
//
//  Reminders used to be a row on a tab: nothing was ever scheduled, so an appointment passed
//  silently unless the app was already open. This schedules the same data as real local
//  notifications and keeps the schedule in step with the notes - which means edits, "mark done"
//  ticks, deletes and the assistant's own changes all move the notification with them.
//
//  Inside a container like LiveContainer, guest apps share another app's process and iOS does not
//  deliver their notifications. That is the container, not this code: build and install normally
//  (or run from Xcode) to see them arrive.
//

import Foundation
import SwiftUI
import UIKit
import UserNotifications

/// Shows the notification while the app is in the foreground instead of swallowing it, and keeps
/// it out of the "no delegate, so nothing is presented" trap that makes a reminder look broken.
final class ReminderNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }

    /// Tapping the notification is treated as "show me that note", so a reminder is a way into the
    /// app rather than a dead-end banner.
    ///
    /// The id is parked on the scheduler instead of being posted through NotificationCenter: when iOS
    /// launches the app from a banner, the delegate runs before any view has subscribed to anything,
    /// and the tap used to disappear.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if let idString = response.notification.request.content.userInfo["noteID"] as? String,
           let id = UUID(uuidString: idString) {
            Task { @MainActor in ReminderScheduler.shared.noteTappedFromNotification(id) }
        }
        completionHandler()
    }
}

@MainActor
final class ReminderScheduler: ObservableObject {
    static let shared = ReminderScheduler()

    /// Whether iOS has accepted notification requests, and whether the user wants them at all.
    @Published private(set) var authorizationGranted = false
    @Published private(set) var authorizationDenied = false
    /// Count of what is currently on the system schedule, shown in Settings so "no notification"
    /// can be told apart from "nothing to notify about".
    @Published private(set) var scheduledCount = 0
    /// A reminder the user tapped, waiting for the root view to open it.
    @Published var pendingNoteToOpen: UUID?

    private let center = UNUserNotificationCenter.current()
    private let enabledKey = "sahand_info_reminder_notifications_v1"
    private let prefix = "sahand-reminder-"
    /// iOS keeps at most 64 pending requests per app, so the nearest ones win rather than silently
    /// dropping whatever sort order happened to put last.
    private let systemLimit = 60
    private var didConfigure = false

    private init() {}

    var notificationsWanted: Bool {
        get {
            if UserDefaults.standard.object(forKey: enabledKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: enabledKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: enabledKey)
            if newValue { requestAuthorization() } else { cancelAll() }
        }
    }

    var notificationsEnabled: Bool { notificationsWanted }

    func noteTappedFromNotification(_ id: UUID) {
        pendingNoteToOpen = id
    }

    func configureOnce() {
        guard !didConfigure else { return }
        didConfigure = true
        center.delegate = ReminderDelegateHolder.shared.value
        requestAuthorization()
    }

    /// Re-reads what iOS will actually do, because the authorization *request* only ever reports the
    /// answer the user gave once. Turn notifications off in the Settings app afterwards and this app
    /// would otherwise go on claiming "On — 3 reminders scheduled" while nothing arrived.
    func refreshAuthorizationStatus() {
        center.getNotificationSettings { settings in
            let status = settings.authorizationStatus
            let allowedByiOS = status == .authorized || status == .provisional
            // "Authorized but no banner style" is what turning notifications off in Settings looks
            // like from the inside, and it means nothing will be visible - so the truth is "blocked",
            // not "on, 3 scheduled".
            let silenced = allowedByiOS && settings.alertStyle == .none
            Task { @MainActor in
                self.authorizationGranted = allowedByiOS && !silenced
                self.authorizationDenied = status == .denied || silenced
                if self.authorizationGranted { self.rescheduleAll() }
            }
        }
    }

    /// Called when the app comes to the foreground: the badge is the count of undelivered reminders,
    /// so reading the app clears it.
    func clearBadge() {
        UIApplication.shared.applicationIconBadgeNumber = 0
    }

    func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            Task { @MainActor in
                self.authorizationGranted = granted
                self.authorizationDenied = !granted
                if granted { self.rescheduleAll() } else { self.cancelAll() }
            }
        }
    }

    func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    /// Called after every change to the notes, so the schedule can never drift from the data.
    func sync(with notes: [Note]) {
        pending = notes
        rescheduleAll()
    }

    private var pending: [Note] = []

    private func rescheduleAll() {
        guard notificationsWanted, authorizationGranted else {
            cancelAllKeepingCount()
            return
        }
        let upcoming = notesWithFutureReminders
        center.removeAllPendingNotificationRequests()
        for note in upcoming.prefix(systemLimit) {
            guard let date = note.reminderDate else { continue }
            addRequest(for: note, at: date)
        }
        scheduledCount = min(upcoming.count, systemLimit)
    }

    private var notesWithFutureReminders: [Note] {
        let now = Date()
        return pending
            .filter { ($0.reminderDate ?? .distantPast) > now && !$0.isReminderCompleted }
            .sorted { ($0.reminderDate ?? .distantFuture) < ($1.reminderDate ?? .distantFuture) }
    }

    private func addRequest(for note: Note, at date: Date) {
        let content = UNMutableNotificationContent()
        content.title = note.title.isEmpty ? "Reminder" : note.title
        let body = note.previewText
        content.body = body.count > 140 ? String(body.prefix(137)) + "…" : body
        content.sound = .default
        content.userInfo = ["noteID": note.id.uuidString]
        // The permission asks for a badge, so the badge is used: it counts what is still on the
        // schedule and is cleared the moment the app is opened. Promising it and never setting it is
        // how a notification app ends up with a red dot that no one can get rid of.
        content.badge = 1

        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        center.add(UNNotificationRequest(identifier: prefix + note.id.uuidString,
                                        content: content,
                                        trigger: trigger),
                    withCompletionHandler: nil)
    }

    private func cancelAllKeepingCount() {
        center.removeAllPendingNotificationRequests()
        scheduledCount = 0
    }

    func cancel(note id: UUID) {
        center.removePendingNotificationRequests(withIdentifiers: [prefix + id.uuidString])
    }

    func cancelAll() {
        center.removeAllPendingNotificationRequests()
        scheduledCount = 0
    }

    /// The text the Settings row shows - deliberately specific, because "notifications are off"
    /// and "you have nothing scheduled" feel identical from the phone.
    var statusLine: String {
        if authorizationDenied {
            return "Notifications are off for this app in iOS Settings — turn them on to be reminded."
        }
        if !notificationsWanted {
            return "Off. Your reminders still show on the Date tab, they just stay quiet."
        }
        if !authorizationGranted {
            return authorizationDenied
                ? "Blocked in iOS Settings — turn notifications on for this app to be reminded."
                : "Waiting for permission. Tap Allow when iOS asks."
        }
        let upcoming = notesWithFutureReminders.count
        if upcoming == 0 { return "On — nothing upcoming to notify about." }
        if upcoming > systemLimit {
            return "On — the nearest \(systemLimit) of \(upcoming) reminders are scheduled (iOS limit)."
        }
        return "On — \(upcoming) reminder\(upcoming == 1 ? "" : "s") scheduled."
    }
}

/// Keeps the UNUserNotificationCenter delegate alive for the life of the process, without making the
/// SwiftUI App struct carry UIKit plumbing.
@MainActor
final class ReminderDelegateHolder {
    static let shared = ReminderDelegateHolder()
    let value = ReminderNotificationDelegate()
    private init() {}
}
