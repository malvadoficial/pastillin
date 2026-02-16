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
