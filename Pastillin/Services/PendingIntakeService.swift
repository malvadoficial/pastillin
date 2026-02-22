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

        // Última toma pendiente por medicamento.
        var latestPendingByMedication: [UUID: Date] = [:]
        // Última toma marcada como tomada por medicamento.
        var latestTakenByMedication: [UUID: Date] = [:]

        for log in logs {
            let dayKey = calendar.startOfDay(for: log.dateKey)
            let medID = log.medicationID

            if log.isTaken {
                if dayKey <= today {
                    if let existingTakenDay = latestTakenByMedication[medID] {
                        if dayKey > existingTakenDay {
                            latestTakenByMedication[medID] = dayKey
                        }
                    } else {
                        latestTakenByMedication[medID] = dayKey
                    }
                }
                continue
            }

            guard dayKey < today else { continue }
            guard dayKey >= start else { continue }
            guard let med = medsByID[medID] else { continue }
            guard med.kind == .scheduled else { continue }
            guard isEligibleForPending(medication: med) else { continue }

            if let existingPendingDay = latestPendingByMedication[medID] {
                if dayKey > existingPendingDay {
                    latestPendingByMedication[medID] = dayKey
                }
            } else {
                latestPendingByMedication[medID] = dayKey
            }
        }

        let validMedicationIDs = latestPendingByMedication.compactMap { medID, latestPendingDay -> UUID? in
            if let latestTakenDay = latestTakenByMedication[medID], latestTakenDay > latestPendingDay {
                return nil
            }
            return medID
        }

        return Set(validMedicationIDs).count
    }

    private static func isEligibleForPending(medication: Medication) -> Bool {
        guard medication.kind == .scheduled else { return false }
        guard medication.startDateRaw != nil else { return false }
        return !(medication.repeatUnit == .day && medication.interval == 1)
    }
}
