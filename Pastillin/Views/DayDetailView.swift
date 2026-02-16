import SwiftUI
import SwiftData

struct DayDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query private var medications: [Medication]
    @Query private var logs: [IntakeLog]

    let day: Date   // viene del calendario (puede ser cualquier día)
    @State private var selected: SelectedWrapper? = nil
    @State private var showingAddTypeDialog = false
    @State private var addMode: DayAddMode? = nil

    var body: some View {
        let cal = Calendar.current
        let dayKey = cal.startOfDay(for: day)

        NavigationStack {
            List {
                let items = rowsForDay(dayKey)

                if items.isEmpty {
                    EmptyMedicinesStateView()
                } else {
                    ForEach(items, id: \.med.id) { item in
                        Button {
                            selected = SelectedWrapper(med: item.med, log: item.log, dayKey: dayKey)
                        } label: {
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

                                Text(item.log.isTaken ? L10n.tr("status_taken_masc") : L10n.tr("status_not_taken_masc"))
                                    .font(.subheadline)
                                    .foregroundStyle(item.log.isTaken ? AppTheme.brandBlue : .secondary)
                            }
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(Fmt.dayLong(dayKey))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(AppTheme.brandYellow)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                        .opacity(showingAddTypeDialog ? 0.35 : 1)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.tr("button_close")) { dismiss() }
                        .disabled(showingAddTypeDialog)
                        .opacity(showingAddTypeDialog ? 0.35 : 1)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingAddTypeDialog = true } label: { Image(systemName: "plus") }
                        .disabled(showingAddTypeDialog)
                        .opacity(showingAddTypeDialog ? 0.35 : 1)
                }
            }
            .overlay {
                if showingAddTypeDialog {
                    DayAddMedicationTypeOverlay(
                        onChooseScheduled: {
                            showingAddTypeDialog = false
                            addMode = .scheduled
                        },
                        onChooseOccasional: {
                            showingAddTypeDialog = false
                            addMode = .occasional
                        },
                        onCancel: { showingAddTypeDialog = false }
                    )
                    .transition(.opacity)
                    .zIndex(2)
                }
            }
            .onAppear {
                // Crea logs para ese día (por defecto No tomado) para todas las medicinas que tocan
                try? LogService.ensureLogs(for: dayKey, modelContext: modelContext)
            }
            .onChange(of: medications.count) { _, _ in
                try? LogService.ensureLogs(for: dayKey, modelContext: modelContext)
            }
            .sheet(item: $selected) { wrap in
                MedicationLogDetailView(
                    medication: wrap.med,
                    dayKey: wrap.dayKey,
                    log: wrap.log
                )
            }
            .sheet(item: $addMode) { mode in
                EditMedicationView(
                    medication: nil,
                    creationKind: mode.kind,
                    initialStartDate: dayKey
                )
            }
        }
    }

    // MARK: - Data

    private func rowsForDay(_ dayKey: Date) -> [(med: Medication, log: IntakeLog)] {
        let cal = Calendar.current

        let active = medications.filter { $0.isActive }
        let due = active
            .filter { $0.isDue(on: dayKey, calendar: cal) }
            .sorted {
            let o0 = $0.sortOrder ?? 0
            let o1 = $1.sortOrder ?? 0
            if o0 != o1 { return o0 < o1 }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }

        let dayLogs = logs.filter { cal.isDate($0.dateKey, inSameDayAs: dayKey) }

        // onAppear asegura que existen; aun así, por seguridad, solo devolvemos los que tienen log
        return due.compactMap { med in
            guard let log = dayLogs.first(where: { $0.medicationID == med.id }) else { return nil }
            return (med, log)
        }
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
}

private enum DayAddMode: Int, Identifiable {
    case scheduled
    case occasional

    var id: Int { rawValue }

    var kind: MedicationKind {
        switch self {
        case .scheduled: return .scheduled
        case .occasional: return .occasional
        }
    }
}


private struct DayAddMedicationTypeOverlay: View {
    let onChooseScheduled: () -> Void
    let onChooseOccasional: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.62)
                .ignoresSafeArea()
                .onTapGesture(perform: onCancel)

            VStack(spacing: 12) {
                Text(L10n.tr("medication_add_type_title"))
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button(action: onChooseScheduled) {
                    Label(L10n.tr("medication_add_scheduled"), systemImage: "calendar.badge.plus")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)

                Button(action: onChooseOccasional) {
                    Label(L10n.tr("medication_add_occasional"), systemImage: "plus.circle")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)

                Divider()

                Button(L10n.tr("button_cancel"), action: onCancel)
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
