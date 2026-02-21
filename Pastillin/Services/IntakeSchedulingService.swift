import Foundation
import SwiftData

enum IntakeSchedulingService {
    private static let threeTimesDailySlots: [(hour: Int, minute: Int)] = [(8, 0), (15, 0), (22, 0)]

    static func bootstrapScheduledIntakes(
        modelContext: ModelContext,
        referenceDate: Date = Date(),
        horizonDays: Int = 365
    ) throws {
        let medications = try modelContext.fetch(FetchDescriptor<Medication>())
        for medication in medications where medication.isActive && medication.kind == .scheduled {
            try generateInitialIntakes(
                for: medication,
                modelContext: modelContext,
                referenceDate: referenceDate,
                horizonDays: horizonDays
            )
        }
    }

    static func generateInitialIntakes(
        for medication: Medication,
        modelContext: ModelContext,
        referenceDate: Date = Date(),
        horizonDays: Int = 365
    ) throws {
        guard medication.isActive else { return }
        guard medication.kind == .scheduled else { return }

        let calendar = Calendar.current
        let existing = try fetchIntakes(for: medication.id, modelContext: modelContext)
        var existingScheduledKeys = Set(
            existing
                .filter { $0.source == .scheduled }
                .map {
                    scheduledKey(
                        for: $0.scheduledAt,
                        repeatUnit: medication.repeatUnit,
                        threeTimesDaily: medication.threeTimesDaily,
                        calendar: calendar
                    )
                }
        )

        if medication.repeatUnit == .hour {
            let boundedHorizon = max(30, horizonDays)
            let horizonStart = calendar.startOfDay(for: referenceDate)
            let horizonEndExclusive = calendar.date(byAdding: .day, value: boundedHorizon + 1, to: horizonStart) ?? horizonStart
            let rangeStart = max(medication.startDate, referenceDate)
            let rangeEndExclusive = min(endDateExclusive(for: medication, calendar: calendar), horizonEndExclusive)
            guard rangeStart < rangeEndExclusive else { return }

            let step = TimeInterval(max(1, medication.interval) * 3600)
            var occurrence = firstOccurrence(onOrAfter: rangeStart, start: medication.startDate, step: step)

            while occurrence < rangeEndExclusive {
                let normalized = normalizedHourlyOccurrence(occurrence, calendar: calendar)
                let key = scheduledKey(
                    for: normalized,
                    repeatUnit: .hour,
                    threeTimesDaily: false,
                    calendar: calendar
                )
                if !existingScheduledKeys.contains(key) {
                    modelContext.insert(
                        Intake(
                            medicationID: medication.id,
                            scheduledAt: normalized,
                            source: .scheduled
                        )
                    )
                    existingScheduledKeys.insert(key)
                }
                occurrence = occurrence.addingTimeInterval(step)
            }
        } else {
            let today = calendar.startOfDay(for: referenceDate)
            let start = max(calendar.startOfDay(for: medication.startDate), today)

            let boundedHorizon = max(30, horizonDays)
            let horizonEnd = calendar.date(byAdding: .day, value: boundedHorizon, to: today) ?? today
            let rangeEnd = endDate(for: medication, horizonEnd: horizonEnd, calendar: calendar)
            guard start <= rangeEnd else { return }

            var cursor = start
            while cursor <= rangeEnd {
                if medication.isDue(on: cursor, calendar: calendar) {
                    if medication.threeTimesDaily {
                        for slot in threeTimesDailySlots {
                            let scheduledAt = calendar.date(
                                bySettingHour: slot.hour,
                                minute: slot.minute,
                                second: 0,
                                of: cursor
                            ) ?? cursor
                            let key = scheduledKey(
                                for: scheduledAt,
                                repeatUnit: medication.repeatUnit,
                                threeTimesDaily: medication.threeTimesDaily,
                                calendar: calendar
                            )
                            if existingScheduledKeys.contains(key) { continue }
                            modelContext.insert(
                                Intake(
                                    medicationID: medication.id,
                                    scheduledAt: scheduledAt,
                                    source: .scheduled
                                )
                            )
                            existingScheduledKeys.insert(key)
                        }
                    } else {
                        let key = scheduledKey(
                            for: cursor,
                            repeatUnit: medication.repeatUnit,
                            threeTimesDaily: medication.threeTimesDaily,
                            calendar: calendar
                        )
                        if !existingScheduledKeys.contains(key) {
                            modelContext.insert(
                                Intake(
                                    medicationID: medication.id,
                                    scheduledAt: midday(for: cursor, calendar: calendar),
                                    source: .scheduled
                                )
                            )
                            existingScheduledKeys.insert(key)
                        }
                    }
                }
                guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
                cursor = next
            }
        }

        try deduplicateScheduledIntakes(
            for: medication.id,
            repeatUnit: medication.repeatUnit,
            threeTimesDaily: medication.threeTimesDaily,
            modelContext: modelContext,
            calendar: calendar
        )
        try modelContext.save()
    }

    static func regenerateFutureIntakes(
        for medication: Medication,
        from pivotDate: Date,
        modelContext: ModelContext,
        horizonDays: Int = 365
    ) throws {
        guard medication.kind == .scheduled else { return }

        let calendar = Calendar.current
        let existing = try fetchIntakes(for: medication.id, modelContext: modelContext)
        let takenIntakeIDs = try takenIntakeIDs(modelContext: modelContext)

        for intake in existing
        where intake.source == .scheduled
            && shouldDeleteScheduledIntake(
                scheduledAt: intake.scheduledAt,
                from: pivotDate,
                repeatUnit: medication.repeatUnit,
                calendar: calendar
            )
            && !takenIntakeIDs.contains(intake.id) {
            modelContext.delete(intake)
        }

        try generateInitialIntakes(
            for: medication,
            modelContext: modelContext,
            referenceDate: pivotDate,
            horizonDays: horizonDays
        )
    }

    static func moveScheduledIntakeAndReflow(
        medication: Medication,
        intake: Intake,
        newDate: Date,
        modelContext: ModelContext,
        horizonDays: Int = 365
    ) throws {
        guard medication.kind == .scheduled else {
            intake.scheduledAt = newDate
            try modelContext.save()
            return
        }

        let calendar = Calendar.current
        if medication.repeatUnit == .hour {
            let normalizedNewDate = normalizedHourlyOccurrence(newDate, calendar: calendar)
            intake.scheduledAt = normalizedNewDate
            medication.startDate = normalizedNewDate

            try regenerateFutureIntakes(
                for: medication,
                from: normalizedNewDate.addingTimeInterval(1),
                modelContext: modelContext,
                horizonDays: horizonDays
            )
        } else {
            let newKey = calendar.startOfDay(for: newDate)
            if medication.threeTimesDaily {
                let hm = calendar.dateComponents([.hour, .minute], from: intake.scheduledAt)
                var comps = calendar.dateComponents([.year, .month, .day], from: newKey)
                comps.hour = hm.hour
                comps.minute = hm.minute
                intake.scheduledAt = calendar.date(from: comps) ?? midday(for: newDate, calendar: calendar)
            } else {
                intake.scheduledAt = midday(for: newDate, calendar: calendar)
            }
            medication.startDate = newKey

            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: newKey) else {
                try modelContext.save()
                return
            }

            try regenerateFutureIntakes(
                for: medication,
                from: nextDay,
                modelContext: modelContext,
                horizonDays: horizonDays
            )
        }
    }

    static func deduplicateScheduledIntakes(
        for medicationID: UUID,
        repeatUnit: RepeatUnit,
        threeTimesDaily: Bool,
        modelContext: ModelContext,
        calendar: Calendar = .current
    ) throws {
        let takenIntakes = try takenIntakeIDs(modelContext: modelContext)
        let all = try fetchIntakes(for: medicationID, modelContext: modelContext)
            .filter { $0.source == .scheduled }

        let grouped = Dictionary(grouping: all) {
            scheduledKey(
                for: $0.scheduledAt,
                repeatUnit: repeatUnit,
                threeTimesDaily: threeTimesDaily,
                calendar: calendar
            )
        }

        for (_, duplicates) in grouped where duplicates.count > 1 {
            let keepTaken = duplicates.first(where: { takenIntakes.contains($0.id) })
            let keep = keepTaken ?? duplicates.min { lhs, rhs in
                if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
                return lhs.id.uuidString < rhs.id.uuidString
            }
            for intake in duplicates where intake.id != keep?.id {
                if takenIntakes.contains(intake.id) { continue }
                modelContext.delete(intake)
            }
        }
    }

    private static func fetchIntakes(for medicationID: UUID, modelContext: ModelContext) throws -> [Intake] {
        let descriptor = FetchDescriptor<Intake>(
            predicate: #Predicate { $0.medicationID == medicationID }
        )
        return try modelContext.fetch(descriptor)
    }

    private static func takenIntakeIDs(modelContext: ModelContext) throws -> Set<UUID> {
        let allLogs = try modelContext.fetch(FetchDescriptor<IntakeLog>())
        return Set(
            allLogs.compactMap { log in
                guard log.isTaken, let intakeID = log.intakeID else { return nil }
                return intakeID
            }
        )
    }

    private static func endDate(for medication: Medication, horizonEnd: Date, calendar: Calendar) -> Date {
        guard let medicationEnd = medication.endDate else { return horizonEnd }
        return min(calendar.startOfDay(for: medicationEnd), horizonEnd)
    }

    private static func endDateExclusive(for medication: Medication, calendar: Calendar) -> Date {
        guard let medicationEnd = medication.endDate else { return .distantFuture }
        let endDay = calendar.startOfDay(for: medicationEnd)
        return calendar.date(byAdding: .day, value: 1, to: endDay) ?? medicationEnd
    }

    private static func midday(for day: Date, calendar: Calendar) -> Date {
        var components = calendar.dateComponents([.year, .month, .day], from: day)
        components.hour = 12
        components.minute = 0
        components.second = 0
        return calendar.date(from: components) ?? day
    }

    private static func normalizedHourlyOccurrence(_ date: Date, calendar: Calendar) -> Date {
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return calendar.date(from: components) ?? date
    }

    private static func firstOccurrence(onOrAfter target: Date, start: Date, step: TimeInterval) -> Date {
        guard target > start else { return start }
        let delta = target.timeIntervalSince(start)
        let jumps = Int(ceil(delta / step))
        return start.addingTimeInterval(Double(jumps) * step)
    }

    private static func shouldDeleteScheduledIntake(
        scheduledAt: Date,
        from pivotDate: Date,
        repeatUnit: RepeatUnit,
        calendar: Calendar
    ) -> Bool {
        if repeatUnit == .hour {
            return scheduledAt >= pivotDate
        }
        return calendar.startOfDay(for: scheduledAt) >= calendar.startOfDay(for: pivotDate)
    }

    private static func scheduledKey(
        for date: Date,
        repeatUnit: RepeatUnit,
        threeTimesDaily: Bool,
        calendar: Calendar
    ) -> Double {
        if repeatUnit == .hour || threeTimesDaily {
            return normalizedHourlyOccurrence(date, calendar: calendar).timeIntervalSinceReferenceDate
        }
        return calendar.startOfDay(for: date).timeIntervalSinceReferenceDate
    }

}
