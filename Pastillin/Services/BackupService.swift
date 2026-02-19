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
                startDate: m.startDate ?? Date(),
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
            med.startDateRaw = m.startDate
            med.cimaNRegistro = m.cimaNRegistro
            med.cimaCN = m.cimaCN
            med.cimaNombreCompleto = m.cimaNombreCompleto
            med.cimaPrincipioActivo = m.cimaPrincipioActivo
            med.cimaLaboratorio = m.cimaLaboratorio
            med.cimaProspectoURL = m.cimaProspectoURL
            med.inShoppingCartRaw = m.inShoppingCartRaw
            med.shoppingCartSortOrderRaw = m.shoppingCartSortOrderRaw
            med.shoppingCartExpectedEndDate = m.shoppingCartExpectedEndDate
            med.shoppingCartRemainingDosesRaw = m.shoppingCartRemainingDosesRaw
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
            app.reminderTimesInMinutes = s.reminderTimesRaw ?? [s.reminderHour * 60 + s.reminderMinute]
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
        NotificationService.cancelDailyReminder()

        // Evita invalidar el objeto que SettingsView puede estar observando en tiempo real.
        if let app = currentSettings.first(where: { $0.id == "app" }) ?? currentSettings.first {
            app.id = "app"
            app.reminderTimesInMinutes = [10 * 60]
            app.reminderHour = 10
            app.reminderMinute = 0
            app.notificationsEnabled = false
            app.medicationAutocompleteEnabled = true
            app.uiAppearanceMode = .system
        } else {
            modelContext.insert(AppSettings())
        }

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
                    startDate: $0.startDateRaw,
                    endDate: $0.endDate,
                    cimaNRegistro: $0.cimaNRegistro,
                    cimaCN: $0.cimaCN,
                    cimaNombreCompleto: $0.cimaNombreCompleto,
                    cimaPrincipioActivo: $0.cimaPrincipioActivo,
                    cimaLaboratorio: $0.cimaLaboratorio,
                    cimaProspectoURL: $0.cimaProspectoURL,
                    inShoppingCartRaw: $0.inShoppingCartRaw,
                    shoppingCartSortOrderRaw: $0.shoppingCartSortOrderRaw,
                    shoppingCartExpectedEndDate: $0.shoppingCartExpectedEndDate,
                    shoppingCartRemainingDosesRaw: $0.shoppingCartRemainingDosesRaw
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
                    reminderTimesRaw: $0.reminderTimesRaw,
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
    let startDate: Date?
    let endDate: Date?
    let cimaNRegistro: String?
    let cimaCN: String?
    let cimaNombreCompleto: String?
    let cimaPrincipioActivo: String?
    let cimaLaboratorio: String?
    let cimaProspectoURL: String?
    let inShoppingCartRaw: Bool?
    let shoppingCartSortOrderRaw: Int?
    let shoppingCartExpectedEndDate: Date?
    let shoppingCartRemainingDosesRaw: Int?
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
    let reminderTimesRaw: [Int]?
    let medicationAutocompleteEnabledRaw: Bool?
}
