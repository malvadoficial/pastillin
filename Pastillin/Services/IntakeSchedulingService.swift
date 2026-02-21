import Foundation
import SwiftData

enum IntakeSchedulingService {
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
        let today = calendar.startOfDay(for: referenceDate)
        let start = max(calendar.startOfDay(for: medication.startDate), today)

        let boundedHorizon = max(30, horizonDays)
        let horizonEnd = calendar.date(byAdding: .day, value: boundedHorizon, to: today) ?? today
        let rangeEnd = endDate(for: medication, horizonEnd: horizonEnd, calendar: calendar)
        guard start <= rangeEnd else { return }

        let existing = try fetchIntakes(for: medication.id, modelContext: modelContext)
        var existingScheduledKeys = Set(
            existing
                .filter { $0.source == .scheduled }
                .map { calendar.startOfDay(for: $0.scheduledAt).timeIntervalSinceReferenceDate }
        )

        var cursor = start
        while cursor <= rangeEnd {
            if medication.isDue(on: cursor, calendar: calendar) {
                let key = cursor.timeIntervalSinceReferenceDate
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
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }

        try deduplicateScheduledIntakes(for: medication.id, modelContext: modelContext, calendar: calendar)
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
        let pivotKey = calendar.startOfDay(for: pivotDate)
        let existing = try fetchIntakes(for: medication.id, modelContext: modelContext)
        let takenIntakeIDs = try takenIntakeIDs(modelContext: modelContext)

        for intake in existing
        where intake.source == .scheduled
            && calendar.startOfDay(for: intake.scheduledAt) >= pivotKey
            && !takenIntakeIDs.contains(intake.id) {
            modelContext.delete(intake)
        }

        try generateInitialIntakes(
            for: medication,
            modelContext: modelContext,
            referenceDate: pivotKey,
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
        let newKey = calendar.startOfDay(for: newDate)

        intake.scheduledAt = midday(for: newDate, calendar: calendar)
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

    static func deduplicateScheduledIntakes(
        for medicationID: UUID,
        modelContext: ModelContext,
        calendar: Calendar = .current
    ) throws {
        let takenIntakes = try takenIntakeIDs(modelContext: modelContext)
        let all = try fetchIntakes(for: medicationID, modelContext: modelContext)
            .filter { $0.source == .scheduled }

        let grouped = Dictionary(grouping: all) {
            calendar.startOfDay(for: $0.scheduledAt).timeIntervalSinceReferenceDate
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

    private static func midday(for day: Date, calendar: Calendar) -> Date {
        var components = calendar.dateComponents([.year, .month, .day], from: day)
        components.hour = 12
        components.minute = 0
        components.second = 0
        return calendar.date(from: components) ?? day
    }
}
