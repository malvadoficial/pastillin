import SwiftUI
import SwiftData
import UIKit

struct MedicationsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var medications: [Medication]

    @State private var showingAddTypeDialog = false
    @State private var addMode: AddMode? = nil
    @State private var editMed: Medication? = nil

    var body: some View {
        NavigationStack {
            List {
                if medications.isEmpty {
                    EmptyMedicinesStateView()
                        .listRowBackground(Color.clear)
                } else {
                    Section {
                        ForEach(scheduledMeds) { med in
                            medicationRow(med)
                        }
                        .onDelete { delete($0, in: scheduledMeds) }
                        .onMove { move(from: $0, to: $1, in: .scheduled) }
                    } header: {
                        Text(L10n.tr("medications_section_scheduled"))
                            .foregroundStyle(AppTheme.brandYellow)
                    }

                    Section {
                        ForEach(occasionalMeds) { med in
                            medicationRow(med)
                        }
                        .onDelete { delete($0, in: occasionalMeds) }
                        .onMove { move(from: $0, to: $1, in: .occasional) }
                    } header: {
                        Text(L10n.tr("medications_section_occasional"))
                            .foregroundStyle(AppTheme.brandYellow)
                    }
                }
            }
            .safeAreaPadding(.bottom, 84)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    NavigationTitleWithIcon(
                        title: L10n.tr("medications_title"),
                        systemImage: "pills",
                        color: AppTheme.brandYellow
                    )
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingAddTypeDialog = true } label: { Image(systemName: "plus") }
                        .foregroundStyle(AppTheme.brandYellow)
                }
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                        .tint(AppTheme.brandYellow)
                }
            }
            .overlay {
                if showingAddTypeDialog {
                    AddMedicationTypeOverlay(
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
            .onAppear { normalizeSortOrderIfNeeded() }
            .sheet(item: $addMode) { mode in
                EditMedicationView(medication: nil, creationKind: mode.kind)
            }
            .sheet(item: $editMed) { med in
                EditMedicationView(medication: med)
            }
        }
    }

    private var sortedMeds: [Medication] {
        medications.sorted { (a, b) in
            let ao = a.sortOrder ?? 0
            let bo = b.sortOrder ?? 0
            if ao != bo { return ao < bo }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    private var scheduledMeds: [Medication] {
        sortedMeds.filter { $0.kind == .scheduled }
    }

    private var occasionalMeds: [Medication] {
        sortedMeds.filter { $0.kind == .occasional }
    }

    @ViewBuilder
    private func medicationRow(_ med: Medication) -> some View {
        Button {
            editMed = med
        } label: {
            HStack(spacing: 12) {
                if let data = med.photoData,
                   let ui = UIImage(data: data) {
                    Image(uiImage: ui)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 44, height: 44)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    MedicationDefaultArtworkView(
                        kind: MedicationDefaultArtwork.kind(for: med),
                        width: 44,
                        height: 44,
                        cornerRadius: 8
                    )
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(med.name)
                            .font(.headline.weight(.semibold))

                        if !med.isActive {
                            Text(L10n.tr("medication_inactive_badge"))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(AppTheme.brandRed)
                        }

                        if med.kind == .occasional {
                            Text(L10n.tr("medication_occasional_badge"))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(AppTheme.brandBlue)
                        }
                    }

                    summaryView(med)
                }
            }
            .padding(.vertical, 6)
            .opacity(med.isActive ? 1 : 0.55)
        }
        .buttonStyle(.plain)
    }

    private func delete(_ indexSet: IndexSet, in sectionMeds: [Medication]) {
        for i in indexSet {
            let med = sectionMeds[i]
            NotificationService.cancelOccasionalReminder(medicationID: med.id)
            modelContext.delete(med)
        }
        try? modelContext.save()
        normalizeSortOrderIfNeeded(force: true)
    }

    private enum SectionKind {
        case scheduled
        case occasional
    }

    private func move(from source: IndexSet, to destination: Int, in section: SectionKind) {
        var scheduled = scheduledMeds
        var occasional = occasionalMeds
        switch section {
        case .scheduled:
            scheduled.move(fromOffsets: source, toOffset: destination)
        case .occasional:
            occasional.move(fromOffsets: source, toOffset: destination)
        }

        let current = scheduled + occasional
        for (idx, med) in current.enumerated() {
            med.sortOrder = idx
        }
        try? modelContext.save()
    }

    private func normalizeSortOrderIfNeeded(force: Bool = false) {
        let hasNil = medications.contains { $0.sortOrder == nil }
        let hasNonZero = medications.contains { ($0.sortOrder ?? 0) != 0 }
        if !force && !hasNil && hasNonZero { return }

        let ordered = medications.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        for (idx, med) in ordered.enumerated() {
            med.sortOrder = idx
        }
        try? modelContext.save()
    }

    @ViewBuilder
    private func summaryView(_ med: Medication) -> some View {
        if med.kind == .occasional {
            Text(String(format: L10n.tr("summary_occasional_date_line_format"), Fmt.dayMedium(med.startDate)))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else {
            let recurrence = L10n.recurrenceText(repeatUnit: med.repeatUnit, interval: med.interval)
            let isDaily = med.repeatUnit == .day && med.interval == 1
            VStack(alignment: .leading, spacing: 2) {
                Text(recurrence)
                    .font(.subheadline.weight(isDaily ? .bold : .regular))
                    .foregroundStyle(.secondary)

                Text(String(format: L10n.tr("summary_start_line_format"), Fmt.dayMedium(med.startDate)))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let endDate = med.endDate {
                    Text(String(format: L10n.tr("summary_end_line_format"), Fmt.dayMedium(endDate)))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text(L10n.tr("summary_chronic"))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                }
            }
        }
    }
}

private struct AddMedicationTypeOverlay: View {
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

private enum AddMode: Int, Identifiable {
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
