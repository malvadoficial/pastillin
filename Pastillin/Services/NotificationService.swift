//
//  NotificationService.swift
//  MediRecord
//
//  Created by José Manuel Rives on 11/2/26.
//

import Foundation
import UserNotifications

enum NotificationService {
    static let dailyCategory = "DAILY_REMINDER"
    static let openAction = "OPEN_TODAY"
    static let snoozeOneHourAction = "SNOOZE_ONE_HOUR"
    private static let occasionalPrefix = "OCCASIONAL_REMINDER_"

    static func registerCategories() {
        let open = UNNotificationAction(
            identifier: openAction,
            title: L10n.tr("notification_action_open"),
            options: [.foreground]
        )
        let snooze = UNNotificationAction(
            identifier: snoozeOneHourAction,
            title: L10n.tr("notification_action_snooze_1h"),
            options: []
        )
        let category = UNNotificationCategory(
            identifier: dailyCategory,
            actions: [open, snooze],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    static func requestAuthorization() async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    }

    static func scheduleDailyReminder(hour: Int, minute: Int) async throws {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["daily_reminder"])

        var comps = DateComponents()
        comps.hour = hour
        comps.minute = minute

        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)

        let content = UNMutableNotificationContent()
        content.title = L10n.tr("notification_title")
        content.body = L10n.tr("notification_body")
        content.sound = .default
        content.categoryIdentifier = dailyCategory

        let request = UNNotificationRequest(
            identifier: "daily_reminder",
            content: content,
            trigger: trigger
        )
        try await center.add(request)
    }

    static func cancelDailyReminder() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["daily_reminder"])
    }

    static func scheduleSnoozeOneHourReminder() async throws {
        let center = UNUserNotificationCenter.current()

        let content = UNMutableNotificationContent()
        content.title = L10n.tr("notification_title")
        content.body = L10n.tr("notification_body")
        content.sound = .default
        content.categoryIdentifier = dailyCategory

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3600, repeats: false)
        let identifier = "daily_reminder_snooze_\(Int(Date().timeIntervalSince1970))"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        try await center.add(request)
    }

    static func occasionalReminderIdentifier(medicationID: UUID) -> String {
        "\(occasionalPrefix)\(medicationID.uuidString)"
    }

    static func cancelOccasionalReminder(medicationID: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [occasionalReminderIdentifier(medicationID: medicationID)]
        )
    }

    static func scheduleOccasionalReminder(
        medicationID: UUID,
        medicationName: String,
        at date: Date
    ) async throws {
        let center = UNUserNotificationCenter.current()
        let identifier = occasionalReminderIdentifier(medicationID: medicationID)
        center.removePendingNotificationRequests(withIdentifiers: [identifier])

        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)

        let content = UNMutableNotificationContent()
        content.title = L10n.tr("notification_occasional_title")
        content.body = String(format: L10n.tr("notification_occasional_body_format"), medicationName)
        content.sound = .default

        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        try await center.add(request)
    }
}
