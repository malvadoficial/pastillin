import Foundation
import SwiftData

enum BackupService {
    static func generateBackup(modelContext: ModelContext) throws -> URL {
        let payload = try buildPayload(modelContext: modelContext)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(payload)
        let filename = "MediRecordBackup_\(Int(Date().timeIntervalSince1970)).json"
        let outURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try data.write(to: outURL, options: .atomic)
        return outURL
    }

    static func restoreBackup(from url: URL, modelContext: ModelContext) throws {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(BackupPayload.self, from: data)
        try clearAllData(modelContext: modelContext)

        // Restaurar medicaciones
        for m in payload.medications {
            let med = Medication(
                name: m.name,
                note: m.note,
                isActive: m.isActive,
                kind: MedicationKind(rawValue: m.kindRaw ?? MedicationKind.scheduled.rawValue) ?? .scheduled,
                repeatUnit: RepeatUnit(rawValue: m.repeatUnitRaw) ?? .day,
                interval: m.interval,
                startDate: m.startDate,
                endDate: m.endDate
            )
            med.id = m.id
            med.photoData = m.photoData
            med.sortOrder = m.sortOrder
            med.kindRaw = m.kindRaw
            med.occasionalReminderEnabledRaw = m.occasionalReminderEnabledRaw
            med.occasionalReminderHour = m.occasionalReminderHour
            med.occasionalReminderMinute = m.occasionalReminderMinute
            med.skippedDateKeysRaw = m.skippedDateKeysRaw
            med.repeatUnitRaw = m.repeatUnitRaw
            med.cimaNRegistro = m.cimaNRegistro
            med.cimaNombreCompleto = m.cimaNombreCompleto
            med.cimaPrincipioActivo = m.cimaPrincipioActivo
            med.cimaLaboratorio = m.cimaLaboratorio
            med.cimaProspectoURL = m.cimaProspectoURL
            modelContext.insert(med)
        }

        // Restaurar logs
        for l in payload.logs {
            let log = IntakeLog(
                medicationID: l.medicationID,
                dateKey: l.dateKey,
                isTaken: l.isTaken,
                takenAt: l.takenAt
            )
            log.id = l.id
            modelContext.insert(log)
        }

        // Restaurar ajustes
        if let s = payload.settings {
            let app = AppSettings(
                reminderHour: s.reminderHour,
                reminderMinute: s.reminderMinute,
                notificationsEnabled: s.notificationsEnabled,
                medicationAutocompleteEnabled: s.medicationAutocompleteEnabledRaw ?? true
            )
            app.id = s.id
            app.medicationAutocompleteEnabledRaw = s.medicationAutocompleteEnabledRaw
            modelContext.insert(app)
        } else {
            modelContext.insert(AppSettings())
        }

        try modelContext.save()
    }

    static func clearAllData(modelContext: ModelContext) throws {
        let currentMeds = try modelContext.fetch(FetchDescriptor<Medication>())
        let currentLogs = try modelContext.fetch(FetchDescriptor<IntakeLog>())
        let currentSettings = try modelContext.fetch(FetchDescriptor<AppSettings>())

        for item in currentLogs { modelContext.delete(item) }
        for item in currentMeds {
            NotificationService.cancelOccasionalReminder(medicationID: item.id)
            modelContext.delete(item)
        }
        for item in currentSettings { modelContext.delete(item) }
        NotificationService.cancelDailyReminder()
        try modelContext.save()
    }

    private static func buildPayload(modelContext: ModelContext) throws -> BackupPayload {
        let medications = try modelContext.fetch(FetchDescriptor<Medication>())
        let logs = try modelContext.fetch(FetchDescriptor<IntakeLog>())
        let settings = try modelContext.fetch(FetchDescriptor<AppSettings>())

        return BackupPayload(
            version: 1,
            createdAt: Date(),
            medications: medications.map {
                BackupMedication(
                    id: $0.id,
                    name: $0.name,
                    note: $0.note,
                    isActive: $0.isActive,
                    photoData: $0.photoData,
                    sortOrder: $0.sortOrder,
                    kindRaw: $0.kindRaw,
                    occasionalReminderEnabledRaw: $0.occasionalReminderEnabledRaw,
                    occasionalReminderHour: $0.occasionalReminderHour,
                    occasionalReminderMinute: $0.occasionalReminderMinute,
                    skippedDateKeysRaw: $0.skippedDateKeysRaw,
                    repeatUnitRaw: $0.repeatUnitRaw,
                    interval: $0.interval,
                    startDate: $0.startDate,
                    endDate: $0.endDate,
                    cimaNRegistro: $0.cimaNRegistro,
                    cimaNombreCompleto: $0.cimaNombreCompleto,
                    cimaPrincipioActivo: $0.cimaPrincipioActivo,
                    cimaLaboratorio: $0.cimaLaboratorio,
                    cimaProspectoURL: $0.cimaProspectoURL
                )
            },
            logs: logs.map {
                BackupLog(
                    id: $0.id,
                    medicationID: $0.medicationID,
                    dateKey: $0.dateKey,
                    isTaken: $0.isTaken,
                    takenAt: $0.takenAt
                )
            },
            settings: settings.first.map {
                BackupSettings(
                    id: $0.id,
                    reminderHour: $0.reminderHour,
                    reminderMinute: $0.reminderMinute,
                    notificationsEnabled: $0.notificationsEnabled,
                    medicationAutocompleteEnabledRaw: $0.medicationAutocompleteEnabledRaw
                )
            }
        )
    }
}

private struct BackupPayload: Codable {
    let version: Int
    let createdAt: Date
    let medications: [BackupMedication]
    let logs: [BackupLog]
    let settings: BackupSettings?
}

private struct BackupMedication: Codable {
    let id: UUID
    let name: String
    let note: String?
    let isActive: Bool
    let photoData: Data?
    let sortOrder: Int?
    let kindRaw: Int?
    let occasionalReminderEnabledRaw: Bool?
    let occasionalReminderHour: Int?
    let occasionalReminderMinute: Int?
    let skippedDateKeysRaw: [Double]?
    let repeatUnitRaw: Int
    let interval: Int
    let startDate: Date
    let endDate: Date?
    let cimaNRegistro: String?
    let cimaNombreCompleto: String?
    let cimaPrincipioActivo: String?
    let cimaLaboratorio: String?
    let cimaProspectoURL: String?
}

private struct BackupLog: Codable {
    let id: UUID
    let medicationID: UUID
    let dateKey: Date
    let isTaken: Bool
    let takenAt: Date?
}

private struct BackupSettings: Codable {
    let id: String
    let reminderHour: Int
    let reminderMinute: Int
    let notificationsEnabled: Bool
    let medicationAutocompleteEnabledRaw: Bool?
}
