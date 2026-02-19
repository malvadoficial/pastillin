import Foundation
import SwiftData

enum TutorialDemoDataService {
    static func seed(modelContext: ModelContext) throws -> [UUID] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())

        let med1 = Medication(
            name: "Paracetamol 1 g",
            note: nil,
            isActive: true,
            kind: .scheduled,
            repeatUnit: .day,
            interval: 1,
            startDate: cal.date(byAdding: .day, value: -14, to: today) ?? today,
            endDate: nil
        )
        med1.inShoppingCart = true
        med1.shoppingCartSortOrder = 0
        med1.shoppingCartRemainingDoses = 5

        let med2 = Medication(
            name: "Ibuprofeno 600 mg",
            note: nil,
            isActive: true,
            kind: .scheduled,
            repeatUnit: .day,
            interval: 3,
            startDate: cal.date(byAdding: .day, value: -30, to: today) ?? today,
            endDate: nil
        )

        let med3 = Medication(
            name: "Amoxicilina 500 mg",
            note: nil,
            isActive: true,
            kind: .scheduled,
            repeatUnit: .day,
            interval: 1,
            startDate: cal.date(byAdding: .day, value: -7, to: today) ?? today,
            endDate: cal.date(byAdding: .day, value: 7, to: today)
        )

        let med4 = Medication(
            name: "Omeprazol 20 mg",
            note: nil,
            isActive: true,
            kind: .scheduled,
            repeatUnit: .day,
            interval: 1,
            startDate: cal.date(byAdding: .day, value: -10, to: today) ?? today,
            endDate: nil
        )
        med4.inShoppingCart = true
        med4.shoppingCartSortOrder = 1
        med4.shoppingCartRemainingDoses = 2

        let med5 = Medication(
            name: "Paracetamol (uso ocasional)",
            note: nil,
            isActive: true,
            kind: .occasional,
            repeatUnit: .day,
            interval: 1,
            startDate: cal.date(byAdding: .day, value: -2, to: today) ?? today,
            endDate: nil
        )

        for med in [med1, med2, med3, med4, med5] {
            modelContext.insert(med)
        }
        try modelContext.save()

        let from = cal.date(byAdding: .day, value: -35, to: today) ?? today
        let to = cal.date(byAdding: .day, value: 30, to: today) ?? today
        try LogService.ensureLogs(from: from, to: to, modelContext: modelContext)

        let allLogs = try modelContext.fetch(FetchDescriptor<IntakeLog>())

        func setTaken(_ medication: Medication, dayOffset: Int, taken: Bool) {
            guard let day = cal.date(byAdding: .day, value: dayOffset, to: today).map({ cal.startOfDay(for: $0) }) else { return }
            guard let log = allLogs.first(where: { $0.medicationID == medication.id && cal.isDate($0.dateKey, inSameDayAs: day) }) else { return }
            log.isTaken = taken
            log.takenAt = taken ? nil : nil
        }

        // Medicación diaria con mezcla de tomadas y no tomadas.
        setTaken(med1, dayOffset: -4, taken: true)
        setTaken(med1, dayOffset: -3, taken: true)
        setTaken(med1, dayOffset: -2, taken: false)
        setTaken(med1, dayOffset: -1, taken: true)

        // No diaria con una pendiente reciente para la sección Pendientes.
        setTaken(med2, dayOffset: -12, taken: true)
        setTaken(med2, dayOffset: -9, taken: true)
        setTaken(med2, dayOffset: -6, taken: false)

        // Tratamiento con fecha de fin.
        setTaken(med3, dayOffset: -3, taken: true)
        setTaken(med3, dayOffset: -2, taken: true)
        setTaken(med3, dayOffset: -1, taken: false)

        // Otra diaria, útil para colores del calendario.
        setTaken(med4, dayOffset: -3, taken: true)
        setTaken(med4, dayOffset: -2, taken: false)
        setTaken(med4, dayOffset: -1, taken: false)

        // Ocasional tomada en pasado.
        if let occasionalDay = cal.date(byAdding: .day, value: -2, to: today).map({ cal.startOfDay(for: $0) }),
           let existing = allLogs.first(where: { $0.medicationID == med5.id && cal.isDate($0.dateKey, inSameDayAs: occasionalDay) }) {
            existing.isTaken = true
            existing.takenAt = nil
        } else if let occasionalDay = cal.date(byAdding: .day, value: -2, to: today).map({ cal.startOfDay(for: $0) }) {
            modelContext.insert(IntakeLog(medicationID: med5.id, dateKey: occasionalDay, isTaken: true, takenAt: nil))
        }

        try modelContext.save()
        NotificationCenter.default.post(name: .intakeLogsDidChange, object: nil)

        return [med1.id, med2.id, med3.id, med4.id, med5.id]
    }

    static func cleanup(medicationIDs: [UUID], modelContext: ModelContext) throws {
        guard !medicationIDs.isEmpty else { return }
        let idSet = Set(medicationIDs)
        let logs = try modelContext.fetch(FetchDescriptor<IntakeLog>())
        let meds = try modelContext.fetch(FetchDescriptor<Medication>())

        for log in logs where idSet.contains(log.medicationID) {
            modelContext.delete(log)
        }
        for med in meds where idSet.contains(med.id) {
            NotificationService.cancelOccasionalReminder(medicationID: med.id)
            modelContext.delete(med)
        }

        try modelContext.save()
        NotificationCenter.default.post(name: .intakeLogsDidChange, object: nil)
    }
}
