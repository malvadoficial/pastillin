import SwiftUI
import SwiftData
import UIKit

struct DayDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query private var medications: [Medication]
    @Query private var logs: [IntakeLog]
    @Query private var intakes: [Intake]

    let day: Date   // viene del calendario (puede ser cualquier día)
    @State private var selected: SelectedWrapper? = nil
    @State private var addIntakeTarget: AddIntakeTarget? = nil
    @State private var deleteCandidate: DeleteCandidate? = nil
    @State private var suppressRowTap = false

    private var dayKey: Date {
        Calendar.current.startOfDay(for: day)
    }

    private var dayItems: [DayRow] {
        rowsForDay(dayKey)
    }

    var body: some View {
        NavigationStack {
            List {
                if dayItems.isEmpty {
                    EmptyMedicinesStateView()
                } else {
                    ForEach(dayItems) { item in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text(item.med.name)
                                        .font(.headline)

                                if item.med.kind == .occasional {
                                    Text(L10n.tr("medication_occasional_badge_short"))
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(AppTheme.brandBlue)
                                }

                                if let label = slotLabel(for: item) {
                                    Text(label)
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(AppTheme.brandYellow)
                                }
                            }

                                // Hora: si tomada -> HH:mm o "hora no especificada", si no -> "—"
                                if item.log.isTaken {
                                    Text(item.log.takenAt.map { timeString($0) } ?? L10n.tr("time_unspecified"))
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("—")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer()

                            if canToggleLog(on: dayKey) {
                                Button {
                                    toggleTaken(item.log, dayKey: dayKey)
                                } label: {
                                    Text(item.log.isTaken ? L10n.tr("status_taken_masc") : L10n.tr("status_not_taken_masc"))
                                        .font(.footnote.weight(.semibold))
                                        .frame(width: 94, height: 30)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(item.log.isTaken ? AppTheme.brandBlue : AppTheme.brandRed)
                            } else {
                                Text(item.log.isTaken ? L10n.tr("status_taken_masc") : L10n.tr("status_not_taken_masc"))
                                    .font(.subheadline)
                                    .foregroundStyle(item.log.isTaken ? AppTheme.brandBlue : .secondary)
                            }
                        }
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            guard !suppressRowTap else { return }
                            selected = SelectedWrapper(med: item.med, log: item.log, dayKey: dayKey)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if canDeleteScheduled(on: dayKey), item.med.kind == .scheduled {
                                Button(role: .destructive) {
                                    deleteCandidate = DeleteCandidate(
                                        medicationID: item.med.id,
                                        logID: item.log.id,
                                        dayKey: dayKey
                                    )
                                } label: {
                                    Label(L10n.tr("detail_remove_for_day"), systemImage: "trash")
                                }
                                .tint(AppTheme.brandRed)
                            }
                        }
                    }
                }
            }
            .textSelection(.enabled)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(Fmt.dayLong(dayKey))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(AppTheme.brandYellow)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.tr("button_close")) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        addIntakeTarget = AddIntakeTarget(day: dayKey)
                    } label: { Image(systemName: "plus") }
                }
            }
            .onAppear {
                try? IntakeSchedulingService.bootstrapScheduledIntakes(modelContext: modelContext)
                ensureLogsForIntakes(on: dayKey)
            }
            .onChange(of: medications.count) { _, _ in
                try? IntakeSchedulingService.bootstrapScheduledIntakes(modelContext: modelContext)
                ensureLogsForIntakes(on: dayKey)
            }
            .onChange(of: intakes.count) { _, _ in
                ensureLogsForIntakes(on: dayKey)
            }
            .sheet(item: $selected) { wrap in
                MedicationLogDetailView(
                    medication: wrap.med,
                    dayKey: wrap.dayKey,
                    log: wrap.log
                )
            }
            .fullScreenCover(item: $addIntakeTarget) { target in
                DayAddIntakePickerView(
                    day: target.day,
                    medications: medications.filter { $0.isActive },
                    lastTakenByMedication: latestTakenByMedication()
                ) { medication, option in
                    createManualIntake(for: medication, day: target.day, option: option)
                    addIntakeTarget = nil
                }
            }
            .alert(L10n.tr("detail_remove_for_day_title"), isPresented: deleteConfirmationBinding) {
                Button(L10n.tr("button_cancel"), role: .cancel) {
                    deleteCandidate = nil
                }
                Button(L10n.tr("detail_remove_for_day_confirm"), role: .destructive) {
                    deleteScheduledIntakeForSelectedDay()
                }
            } message: {
                Text(L10n.tr("detail_remove_for_day_message"))
            }
        }
    }

    // MARK: - Data

    private func rowsForDay(_ dayKey: Date) -> [DayRow] {
        let cal = Calendar.current
        let dayIntakes = intakes.filter { cal.isDate($0.scheduledAt, inSameDayAs: dayKey) }
        let dayLogs = logs.filter { cal.isDate($0.dateKey, inSameDayAs: dayKey) }
        let medsByID = Dictionary(uniqueKeysWithValues: medications.map { ($0.id, $0) })

        if !dayIntakes.isEmpty {
            let sortedIntakes = dayIntakes.sorted { lhs, rhs in
                let lm = medsByID[lhs.medicationID]
                let rm = medsByID[rhs.medicationID]
                let lo = lm?.sortOrder ?? 0
                let ro = rm?.sortOrder ?? 0
                if lo != ro { return lo < ro }
                if lm?.name != rm?.name {
                    return (lm?.name ?? "").localizedCaseInsensitiveCompare(rm?.name ?? "") == .orderedAscending
                }
                return lhs.scheduledAt < rhs.scheduledAt
            }

            return sortedIntakes.compactMap { intake in
                guard let med = medsByID[intake.medicationID] else { return nil }
                let log = dayLogs.first(where: { $0.intakeID == intake.id })
                    ?? dayLogs.first(where: { $0.medicationID == med.id })
                guard let log else { return nil }
                return DayRow(id: intake.id, med: med, log: log, intake: intake)
            }
        }

        let medsToShow = Set(dayLogs.map(\.medicationID)).compactMap { medsByID[$0] }.sorted {
            let o0 = $0.sortOrder ?? 0
            let o1 = $1.sortOrder ?? 0
            if o0 != o1 { return o0 < o1 }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }

        return medsToShow.compactMap { med in
            guard let log = dayLogs.first(where: { $0.medicationID == med.id }) else { return nil }
            return DayRow(id: log.id, med: med, log: log, intake: nil)
        }
    }

    private func slotLabel(for row: DayRow) -> String? {
        guard row.med.threeTimesDaily, let intake = row.intake else { return nil }
        let hour = Calendar.current.component(.hour, from: intake.scheduledAt)
        if hour < 12 { return L10n.tr("intake_slot_morning") }
        if hour < 20 { return L10n.tr("intake_slot_afternoon") }
        return L10n.tr("intake_slot_night")
    }

    private func ensureLogsForIntakes(on day: Date) {
        let calendar = Calendar.current
        let dayKey = calendar.startOfDay(for: day)
        let dayIntakes = intakes.filter { calendar.isDate($0.scheduledAt, inSameDayAs: dayKey) }
        guard !dayIntakes.isEmpty else { return }

        let existingLogKeys = Set(logs.compactMap { log -> String? in
            guard let intakeID = log.intakeID else { return nil }
            return "\(intakeID.uuidString)-\(calendar.startOfDay(for: log.dateKey).timeIntervalSinceReferenceDate)"
        })

        var inserted = false
        for intake in dayIntakes {
            let key = "\(intake.id.uuidString)-\(dayKey.timeIntervalSinceReferenceDate)"
            if existingLogKeys.contains(key) { continue }
            modelContext.insert(
                IntakeLog(
                    medicationID: intake.medicationID,
                    intakeID: intake.id,
                    dateKey: dayKey,
                    isTaken: false,
                    takenAt: nil
                )
            )
            inserted = true
        }

        if inserted {
            try? modelContext.save()
            NotificationCenter.default.post(name: .intakeLogsDidChange, object: nil)
        }
    }

    private func createManualIntake(for medication: Medication, day: Date, option: DayIntakeAddOption) {
        let calendar = Calendar.current
        let dayKey = calendar.startOfDay(for: day)

        if option == .startSchedule, medication.kind == .scheduled {
            if medication.repeatUnit == .hour {
                let hm = calendar.dateComponents([.hour, .minute], from: medication.startDateRaw ?? Date())
                var comps = calendar.dateComponents([.year, .month, .day], from: dayKey)
                comps.hour = hm.hour
                comps.minute = hm.minute
                medication.startDate = calendar.date(from: comps) ?? dayKey
            } else {
                medication.startDate = dayKey
            }
            medication.setSkipped(false, on: dayKey)
            try? IntakeSchedulingService.regenerateFutureIntakes(
                for: medication,
                from: medication.repeatUnit == .hour ? medication.startDate : dayKey,
                modelContext: modelContext
            )
            ensureLogsForIntakes(on: dayKey)
            return
        }

        let intake = Intake(
            medicationID: medication.id,
            scheduledAt: calendar.date(bySettingHour: 12, minute: 0, second: 0, of: dayKey) ?? dayKey,
            source: option == .startSchedule ? .scheduled : .manual
        )
        modelContext.insert(intake)
        modelContext.insert(
            IntakeLog(
                medicationID: medication.id,
                intakeID: intake.id,
                dateKey: dayKey,
                isTaken: option == .occasionalTaken,
                takenAt: option == .occasionalTaken ? (calendar.isDateInToday(dayKey) ? Date() : nil) : nil
            )
        )
        try? modelContext.save()
        NotificationCenter.default.post(name: .intakeLogsDidChange, object: nil)
    }

    private func latestTakenByMedication() -> [UUID: Date] {
        var result: [UUID: Date] = [:]
        for log in logs where log.isTaken {
            guard let takenAt = log.takenAt else { continue }
            if let existing = result[log.medicationID], existing >= takenAt { continue }
            result[log.medicationID] = takenAt
        }
        return result
    }

    private var deleteConfirmationBinding: Binding<Bool> {
        Binding(
            get: { deleteCandidate != nil },
            set: { newValue in
                if !newValue {
                    deleteCandidate = nil
                }
            }
        )
    }

    private func canToggleLog(on dayKey: Date) -> Bool {
        let cal = Calendar.current
        let target = cal.startOfDay(for: dayKey)
        let today = cal.startOfDay(for: Date())
        return target <= today
    }

    private func canDeleteScheduled(on dayKey: Date) -> Bool {
        true
    }

    private func toggleTaken(_ log: IntakeLog, dayKey: Date) {
        guard canToggleLog(on: dayKey) else { return }

        suppressRowTap = true
        defer {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                suppressRowTap = false
            }
        }

        let cal = Calendar.current
        let isToday = cal.isDateInToday(dayKey)

        if log.isTaken {
            log.isTaken = false
            log.takenAt = nil
        } else {
            log.isTaken = true
            log.takenAt = isToday ? Date() : nil
        }

        try? modelContext.save()
        NotificationCenter.default.post(name: .intakeLogsDidChange, object: nil)
    }

    private func deleteScheduledIntakeForSelectedDay() {
        guard let candidate = deleteCandidate else { return }
        defer { deleteCandidate = nil }

        guard let medication = medications.first(where: { $0.id == candidate.medicationID }) else { return }
        guard medication.kind == .scheduled else { return }
        guard let log = logs.first(where: { $0.id == candidate.logID }) else { return }

        medication.setSkipped(true, on: candidate.dayKey)
        if let intakeID = log.intakeID,
           let intake = intakes.first(where: { $0.id == intakeID }) {
            modelContext.delete(intake)
        }
        modelContext.delete(log)
        try? modelContext.save()
        NotificationCenter.default.post(name: .intakeLogsDidChange, object: nil)
    }

    // MARK: - UI helpers

    private func dayTitle(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = .current
        f.dateStyle = .full
        f.timeStyle = .none
        return f.string(from: d)
    }

    private func timeString(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = .current
        f.dateStyle = .none
        f.timeStyle = .short
        return f.string(from: d)
    }

    // MARK: - Wrapper

    struct SelectedWrapper: Identifiable {
        let id = UUID()
        let med: Medication
        let log: IntakeLog
        let dayKey: Date
    }

    struct DayRow: Identifiable {
        let id: UUID
        let med: Medication
        let log: IntakeLog
        let intake: Intake?
    }

    struct DeleteCandidate {
        let medicationID: UUID
        let logID: UUID
        let dayKey: Date
    }

    struct AddIntakeTarget: Identifiable {
        let id = UUID()
        let day: Date
    }
}

private struct DayAddIntakePickerView: View {
    @Environment(\.dismiss) private var dismiss
    let day: Date
    let medications: [Medication]
    let lastTakenByMedication: [UUID: Date]
    let onSelect: (Medication, DayIntakeAddOption) -> Void
    @State private var searchText = ""
    @State private var selectedMedication: Medication? = nil
    @State private var showTypeSelector = false

    private var uniqueMedications: [Medication] {
        var seen = Set<String>()
        var result: [Medication] = []
        for medication in medications {
            let dedupeKey: String
            if medication.kind == .occasional {
                dedupeKey = "occasional:\(medication.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
            } else {
                dedupeKey = "id:\(medication.id.uuidString)"
            }
            if seen.insert(dedupeKey).inserted {
                result.append(medication)
            }
        }
        return result
    }

    private var filtered: [Medication] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return uniqueMedications.sorted { ($0.sortOrder ?? 0) < ($1.sortOrder ?? 0) }
        }
        return uniqueMedications
            .filter { $0.name.localizedCaseInsensitiveContains(query) }
            .sorted { ($0.sortOrder ?? 0) < ($1.sortOrder ?? 0) }
    }

    private var occasional: [Medication] {
        filtered.filter { $0.kind == .occasional }
    }

    private var scheduled: [Medication] {
        filtered.filter { $0.kind == .scheduled }
    }

    var body: some View {
        NavigationStack {
            List {
                if filtered.isEmpty {
                    Text(L10n.tr("medications_search_no_results"))
                        .foregroundStyle(.secondary)
                } else {
                    if !occasional.isEmpty {
                        Section(L10n.tr("medications_section_occasional")) {
                            ForEach(occasional) { medication in
                                medicationRow(medication)
                            }
                        }
                    }
                    if !scheduled.isEmpty {
                        Section(L10n.tr("medications_section_scheduled")) {
                            ForEach(scheduled) { medication in
                                medicationRow(medication)
                            }
                        }
                    }
                }
            }
            .navigationTitle(Fmt.dayLong(day))
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: L10n.tr("medications_search_placeholder"))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.tr("button_cancel")) { dismiss() }
                }
            }
            .overlay {
                if showTypeSelector, let medication = selectedMedication {
                    ZStack(alignment: .bottom) {
                        Color.black.opacity(0.62)
                            .ignoresSafeArea()
                            .onTapGesture { showTypeSelector = false }

                        VStack(spacing: 12) {
                            Text(L10n.tr("medication_add_type_title"))
                                .font(.headline)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            ForEach(DayIntakeAddOption.options(for: medication.kind), id: \.self) { option in
                                Button(option.title) {
                                    showTypeSelector = false
                                    onSelect(medication, option)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 10)
                                .buttonStyle(.plain)
                            }

                            Divider()

                            Button(L10n.tr("button_cancel")) {
                                showTypeSelector = false
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                        }
                        .padding(16)
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func medicationRow(_ medication: Medication) -> some View {
        Button {
            selectedMedication = medication
            showTypeSelector = true
        } label: {
            HStack(spacing: 10) {
                medicationThumbnail(for: medication)

                VStack(alignment: .leading, spacing: 2) {
                    Text(medication.name)
                        .foregroundStyle(.primary)
                    if let lastTaken = lastTakenByMedication[medication.id] {
                        Text("Última toma: \(Fmt.dayMedium(lastTaken)) \(Fmt.timeShort(lastTaken))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func medicationThumbnail(for medication: Medication) -> some View {
        if let data = medication.photoData,
           let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 34, height: 34)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        } else {
            MedicationDefaultArtworkView(
                kind: MedicationDefaultArtwork.kind(for: medication),
                width: 34,
                height: 34,
                cornerRadius: 7
            )
        }
    }
}

private enum DayIntakeAddOption: Hashable {
    case occasionalTaken
    case startSchedule

    var title: String {
        switch self {
        case .occasionalTaken:
            return "Toma ocasional"
        case .startSchedule:
            return "Comienzo de pauta"
        }
    }

    static func options(for kind: MedicationKind) -> [DayIntakeAddOption] {
        switch kind {
        case .occasional:
            return [.occasionalTaken]
        case .scheduled:
            return [.occasionalTaken, .startSchedule]
        case .unspecified:
            return []
        }
    }
}
