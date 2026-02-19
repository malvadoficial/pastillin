//
//  LogService.swift
//  MediRecord
//
//  Created by José Manuel Rives on 11/2/26.
//
import Foundation
import SwiftData

enum LogService {
    static func dateKey(_ date: Date, calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: date)
    }

    static func ensureLogs(for date: Date, modelContext: ModelContext) throws {
        let cal = Calendar.current
        let key = cal.startOfDay(for: date)

        let meds = try modelContext.fetch(FetchDescriptor<Medication>())
            .filter { $0.isActive }

        let existing = try modelContext.fetch(FetchDescriptor<IntakeLog>())
        let existingSet = Set(existing.filter { cal.isDate($0.dateKey, inSameDayAs: key) }.map { $0.medicationID })

        for med in meds {
            guard med.isDue(on: key, calendar: cal) else { continue }
            if existingSet.contains(med.id) { continue }
            modelContext.insert(IntakeLog(medicationID: med.id, dateKey: key, isTaken: false, takenAt: nil))
        }
        try modelContext.save()
        NotificationCenter.default.post(name: .intakeLogsDidChange, object: nil)
    }

    static func ensureLogs(from startDate: Date, to endDate: Date, modelContext: ModelContext) throws {
        let cal = Calendar.current
        let startKey = cal.startOfDay(for: min(startDate, endDate))
        let endKey = cal.startOfDay(for: max(startDate, endDate))

        let meds = try modelContext.fetch(FetchDescriptor<Medication>())
            .filter { $0.isActive }

        let existing = try modelContext.fetch(FetchDescriptor<IntakeLog>())
        var existingKeys = Set(existing.map {
            "\($0.medicationID.uuidString)-\($0.dateKey.timeIntervalSinceReferenceDate)"
        })

        var cursor = startKey
        while cursor <= endKey {
            for med in meds where med.isDue(on: cursor, calendar: cal) {
                let key = "\(med.id.uuidString)-\(cursor.timeIntervalSinceReferenceDate)"
                if existingKeys.contains(key) { continue }
                modelContext.insert(IntakeLog(medicationID: med.id, dateKey: cursor, isTaken: false, takenAt: nil))
                existingKeys.insert(key)
            }
            guard let next = cal.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }

        try modelContext.save()
        NotificationCenter.default.post(name: .intakeLogsDidChange, object: nil)
    }

    static func moveFutureScheduleAfterTakenOnDate(
        medication: Medication,
        selectedDay: Date,
        takenOnDay: Date,
        now: Date = Date(),
        allLogs: [IntakeLog],
        modelContext: ModelContext
    ) throws {
        let cal = Calendar.current
        let selectedKey = cal.startOfDay(for: selectedDay)
        let takenOnKey = cal.startOfDay(for: takenOnDay)
        guard takenOnKey >= selectedKey else { return }

        let dayOffset = cal.dateComponents([.day], from: selectedKey, to: takenOnKey).day ?? 0
        guard dayOffset > 0 else { return }

        guard let currentStartDate = medication.startDateRaw else { return }

        if let shiftedStart = cal.date(byAdding: .day, value: dayOffset, to: currentStartDate) {
            medication.startDate = cal.startOfDay(for: shiftedStart)
        }

        let selectedDayExistingLog = allLogs.first {
            $0.medicationID == medication.id && cal.isDate($0.dateKey, inSameDayAs: selectedKey)
        }
        let takenOnExistingLog = allLogs.first {
            $0.medicationID == medication.id && cal.isDate($0.dateKey, inSameDayAs: takenOnKey)
        }

        let takenAtValue = cal.isDateInToday(takenOnKey) ? now : nil
        let movedLogID: UUID

        // 1) Mover solo la toma origen al día indicado por el usuario.
        if let selectedDayExistingLog,
           let takenOnExistingLog,
           selectedDayExistingLog.id != takenOnExistingLog.id {
            takenOnExistingLog.isTaken = true
            takenOnExistingLog.takenAt = takenAtValue
            modelContext.delete(selectedDayExistingLog)
            movedLogID = takenOnExistingLog.id
        } else if let selectedDayExistingLog {
            selectedDayExistingLog.dateKey = takenOnKey
            selectedDayExistingLog.isTaken = true
            selectedDayExistingLog.takenAt = takenAtValue
            movedLogID = selectedDayExistingLog.id
        } else if let takenOnExistingLog {
            takenOnExistingLog.isTaken = true
            takenOnExistingLog.takenAt = takenAtValue
            movedLogID = takenOnExistingLog.id
        } else {
            let newLog = IntakeLog(medicationID: medication.id, dateKey: takenOnKey, isTaken: true, takenAt: takenAtValue)
            modelContext.insert(newLog)
            movedLogID = newLog.id
        }

        // 2) Borrar solo tomas futuras (pasado intacto).
        let todayKey = cal.startOfDay(for: now)
        for log in allLogs
        where log.medicationID == medication.id
            && log.dateKey > todayKey
            && log.dateKey >= takenOnKey
            && log.id != movedLogID {
            modelContext.delete(log)
        }

        // 3) Regenerar futuras según la pauta actualizada.
        guard let tomorrowKey = cal.date(byAdding: .day, value: 1, to: todayKey).map({ cal.startOfDay(for: $0) }) else {
            try modelContext.save()
            return
        }
        let horizonKey = cal.date(byAdding: .day, value: 365, to: todayKey).map { cal.startOfDay(for: $0) } ?? tomorrowKey
        let lastKey: Date = {
            if let endDate = medication.endDate {
                return min(cal.startOfDay(for: endDate), horizonKey)
            }
            return horizonKey
        }()

        if tomorrowKey <= lastKey {
            let currentMedicationLogs = try modelContext.fetch(FetchDescriptor<IntakeLog>())
                .filter { $0.medicationID == medication.id }
            var existingFutureKeys = Set(
                currentMedicationLogs
                    .filter {
                        $0.dateKey >= tomorrowKey &&
                        $0.dateKey <= lastKey
                    }
                    .map { cal.startOfDay(for: $0.dateKey).timeIntervalSinceReferenceDate }
            )

            var cursor = tomorrowKey
            while cursor <= lastKey {
                if medication.isDue(on: cursor, calendar: cal) {
                    let keyValue = cursor.timeIntervalSinceReferenceDate
                    if !existingFutureKeys.contains(keyValue) {
                        modelContext.insert(
                            IntakeLog(
                                medicationID: medication.id,
                                dateKey: cursor,
                                isTaken: false,
                                takenAt: nil
                            )
                        )
                        existingFutureKeys.insert(keyValue)
                    }
                }
                guard let next = cal.date(byAdding: .day, value: 1, to: cursor) else { break }
                cursor = next
            }
        }

        try modelContext.save()
        NotificationCenter.default.post(name: .intakeLogsDidChange, object: nil)
    }

    /// Si taken == true:
    /// - si overrideTakenAt != nil => se usa esa fecha/hora concreta
    /// - si overrideTakenAt == nil => se usa Date() (hora real, ideal para "Hoy")
    static func setTaken(_ taken: Bool, for log: IntakeLog, overrideTakenAt: Date? = nil) {
        log.isTaken = taken
        if taken {
            log.takenAt = overrideTakenAt ?? Date()
        } else {
            log.takenAt = nil
        }
    }
}
