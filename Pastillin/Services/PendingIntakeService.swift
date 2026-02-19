import Foundation

enum PendingIntakeService {
    static func pendingMedicationCount(
        medications: [Medication],
        logs: [IntakeLog],
        referenceDate: Date = Date(),
        lookbackDays: Int = 30,
        calendar: Calendar = .current
    ) -> Int {
        let today = calendar.startOfDay(for: referenceDate)
        let start = calendar.date(byAdding: .day, value: -(max(1, lookbackDays) - 1), to: today) ?? today
        let medsByID = Dictionary(uniqueKeysWithValues: medications.map { ($0.id, $0) })

        let missedRows: [(medicationID: UUID, log: IntakeLog)] = logs.compactMap { log in
            let dayKey = calendar.startOfDay(for: log.dateKey)
            guard dayKey < today else { return nil }
            guard dayKey >= start else { return nil }
            guard !log.isTaken else { return nil }
            guard let med = medsByID[log.medicationID] else { return nil }
            guard med.kind == .scheduled else { return nil }
            guard isEligibleForPending(medication: med) else { return nil }
            return (med.id, log)
        }

        var latestPendingByMedication: [UUID: IntakeLog] = [:]
        for row in missedRows {
            if let existing = latestPendingByMedication[row.medicationID] {
                if row.log.dateKey > existing.dateKey {
                    latestPendingByMedication[row.medicationID] = row.log
                }
            } else {
                latestPendingByMedication[row.medicationID] = row.log
            }
        }

        let validMedicationIDs = latestPendingByMedication.compactMap { medID, latestLog -> UUID? in
            let latestDay = calendar.startOfDay(for: latestLog.dateKey)
            let hasLaterTaken = logs.contains { log in
                guard log.medicationID == medID else { return false }
                guard log.isTaken else { return false }
                let candidateDay = calendar.startOfDay(for: log.dateKey)
                return candidateDay > latestDay && candidateDay <= today
            }
            return hasLaterTaken ? nil : medID
        }

        return Set(validMedicationIDs).count
    }

    private static func isEligibleForPending(medication: Medication) -> Bool {
        guard medication.kind == .scheduled else { return false }
        guard medication.startDateRaw != nil else { return false }
        return !(medication.repeatUnit == .day && medication.interval == 1)
    }
}
