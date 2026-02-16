//
//  Models.swift
//  MediRecord
//
//  Created by José Manuel Rives on 11/2/26.
//

import Foundation
import SwiftData

enum RepeatUnit: Int, Codable {
    case day
    case month
}

enum MedicationKind: Int, Codable {
    case scheduled
    case occasional
}

enum UIAppearanceMode: Int, Codable, CaseIterable {
    case system
    case light
    case dark
}

@Model
final class Medication {
    @Attribute(.unique) var id: UUID
    var name: String
    var note: String?
    var isActive: Bool
    var cimaNRegistro: String? = nil
    var cimaNombreCompleto: String? = nil
    var cimaPrincipioActivo: String? = nil
    var cimaLaboratorio: String? = nil
    var cimaProspectoURL: String? = nil

    // Foto (opcional)
    var photoData: Data?

    // Orden personalizado
    var sortOrder: Int?

    // Recurrencia
    var kindRaw: Int?
    var occasionalReminderEnabledRaw: Bool?
    var occasionalReminderHour: Int?
    var occasionalReminderMinute: Int?
    var skippedDateKeysRaw: [Double]?
    var repeatUnitRaw: Int
    var interval: Int                // 1 = cada día / cada mes
    var startDate: Date              // ancla
    var endDate: Date?               // último día incluido

    init(
        name: String,
        note: String? = nil,
        isActive: Bool = true,
        kind: MedicationKind = .scheduled,
        repeatUnit: RepeatUnit = .day,
        interval: Int = 1,
        startDate: Date = Date(),
        endDate: Date? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.note = note
        self.isActive = isActive
        self.photoData = nil
        self.sortOrder = nil
        self.kindRaw = kind.rawValue
        self.occasionalReminderEnabledRaw = false
        self.occasionalReminderHour = nil
        self.occasionalReminderMinute = nil
        self.skippedDateKeysRaw = []
        self.repeatUnitRaw = repeatUnit.rawValue
        self.interval = max(1, interval)
        self.startDate = startDate
        self.endDate = endDate
    }

    var repeatUnit: RepeatUnit {
        get { RepeatUnit(rawValue: repeatUnitRaw) ?? .day }
        set { repeatUnitRaw = newValue.rawValue }
    }

    var kind: MedicationKind {
        get {
            guard let raw = kindRaw else { return .scheduled }
            return MedicationKind(rawValue: raw) ?? .scheduled
        }
        set { kindRaw = newValue.rawValue }
    }

    var occasionalReminderEnabled: Bool {
        get { occasionalReminderEnabledRaw ?? false }
        set { occasionalReminderEnabledRaw = newValue }
    }

    func isSkipped(on dateKey: Date, calendar: Calendar = .current) -> Bool {
        let key = calendar.startOfDay(for: dateKey).timeIntervalSinceReferenceDate
        return (skippedDateKeysRaw ?? []).contains { abs($0 - key) < 0.5 }
    }

    func setSkipped(_ skipped: Bool, on dateKey: Date, calendar: Calendar = .current) {
        let key = calendar.startOfDay(for: dateKey).timeIntervalSinceReferenceDate
        var raw = skippedDateKeysRaw ?? []
        raw.removeAll { abs($0 - key) < 0.5 }
        if skipped {
            raw.append(key)
        }
        skippedDateKeysRaw = raw
    }

    func isDue(on dateKey: Date, calendar: Calendar = .current) -> Bool {
        let startKey = calendar.startOfDay(for: startDate)
        if dateKey < startKey { return false }

        if kind == .occasional {
            return calendar.isDate(startKey, inSameDayAs: dateKey)
        }

        if isSkipped(on: dateKey, calendar: calendar) {
            return false
        }

        if let endDate {
            let endKey = calendar.startOfDay(for: endDate)
            if dateKey > endKey { return false } // fin inclusiva
        }

        let n = max(1, interval)

        switch repeatUnit {
        case .day:
            let diffDays = calendar.dateComponents([.day], from: startKey, to: dateKey).day ?? 0
            return diffDays % n == 0

        case .month:
            // meses entre start y dateKey (ignorando día)
            let startComp = calendar.dateComponents([.year, .month, .day], from: startKey)
            let dateComp  = calendar.dateComponents([.year, .month, .day], from: dateKey)

            guard let sy = startComp.year, let sm = startComp.month,
                  let dy = dateComp.year, let dm = dateComp.month else { return false }

            let monthsDiff = (dy - sy) * 12 + (dm - sm)
            if monthsDiff < 0 { return false }
            if monthsDiff % n != 0 { return false }

            // día objetivo = día del startDate (clamp a fin de mes si no existe)
            let targetDay = startComp.day ?? 1
            let scheduled = Self.scheduledDateFor(year: dy, month: dm, day: targetDay, calendar: calendar)
            return calendar.isDate(scheduled, inSameDayAs: dateKey)
        }
    }

    private static func scheduledDateFor(year: Int, month: Int, day: Int, calendar: Calendar) -> Date {
        // Clamp al último día del mes si el día no existe
        var comps = DateComponents(year: year, month: month, day: 1)
        let firstOfMonth = calendar.date(from: comps) ?? Date()

        let range = calendar.range(of: .day, in: .month, for: firstOfMonth) ?? (1..<29)
        let clampedDay = min(max(day, range.lowerBound), range.upperBound - 1)

        comps.day = clampedDay
        return calendar.startOfDay(for: calendar.date(from: comps) ?? firstOfMonth)
    }
}

@Model
final class IntakeLog {
    @Attribute(.unique) var id: UUID
    var medicationID: UUID
    var dateKey: Date               // startOfDay
    var isTaken: Bool               // false = no tomada, true = tomada
    var takenAt: Date?              // hora real si tomada

    init(medicationID: UUID, dateKey: Date, isTaken: Bool = false, takenAt: Date? = nil) {
        self.id = UUID()
        self.medicationID = medicationID
        self.dateKey = dateKey
        self.isTaken = isTaken
        self.takenAt = takenAt
    }
}

@Model
final class AppSettings {
    @Attribute(.unique) var id: String // siempre "app"
    var reminderHour: Int
    var reminderMinute: Int
    var reminderTimesRaw: [Int]?
    var notificationsEnabled: Bool
    var medicationAutocompleteEnabledRaw: Bool?
    var uiAppearanceModeRaw: Int?

    init(reminderHour: Int = 10, reminderMinute: Int = 0, notificationsEnabled: Bool = false, medicationAutocompleteEnabled: Bool = true, uiAppearanceMode: UIAppearanceMode = .system) {
        self.id = "app"
        self.reminderHour = reminderHour
        self.reminderMinute = reminderMinute
        self.reminderTimesRaw = nil
        self.notificationsEnabled = notificationsEnabled
        self.medicationAutocompleteEnabledRaw = medicationAutocompleteEnabled
        self.uiAppearanceModeRaw = uiAppearanceMode.rawValue
    }

    var reminderTimesInMinutes: [Int] {
        get {
            if let raw = reminderTimesRaw {
                return Self.normalizeReminderTimes(raw)
            }
            let legacy = reminderHour * 60 + reminderMinute
            return Self.normalizeReminderTimes([legacy])
        }
        set {
            let normalized = Self.normalizeReminderTimes(newValue)
            reminderTimesRaw = normalized
            let first = normalized.first ?? (10 * 60)
            reminderHour = first / 60
            reminderMinute = first % 60
        }
    }

    private static func normalizeReminderTimes(_ values: [Int]) -> [Int] {
        let sanitized = values.map { min(max($0, 0), 23 * 60 + 59) }
        let unique = Array(Set(sanitized)).sorted()
        return Array(unique.prefix(3))
    }

    var medicationAutocompleteEnabled: Bool {
        get { medicationAutocompleteEnabledRaw ?? true }
        set { medicationAutocompleteEnabledRaw = newValue }
    }

    var uiAppearanceMode: UIAppearanceMode {
        get {
            guard let raw = uiAppearanceModeRaw else { return .system }
            return UIAppearanceMode(rawValue: raw) ?? .system
        }
        set { uiAppearanceModeRaw = newValue.rawValue }
    }
}
