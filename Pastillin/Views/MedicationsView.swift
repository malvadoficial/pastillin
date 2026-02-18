import SwiftUI
import SwiftData
import UIKit

struct MedicationsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var medications: [Medication]
    @Query private var logs: [IntakeLog]
    @AppStorage("selectedTab") private var selectedTab: AppTab = .medications
    @AppStorage("openShoppingCartFromToday") private var openShoppingCartFromToday: Bool = false
    @AppStorage("shoppingCartDisclaimerShown") private var shoppingCartDisclaimerShown: Bool = false

    @State private var showingAddTypeDialog = false
    @State private var addMode: AddMode? = nil
    @State private var editMed: Medication? = nil
    @State private var showShoppingCart = false
    @State private var showShoppingDisclaimerAlert = false
    @State private var pendingCartMedicationID: UUID? = nil
    @State private var pendingOpenCart = false
    @State private var pendingCount: Int = 0
    @State private var listEditMode: EditMode = .inactive

    private struct OccasionalGroup: Identifiable {
        let id: String
        let medications: [Medication]
        let representative: Medication
    }

    var body: some View {
        NavigationStack {
            medicationsList
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
            .onAppear {
                normalizeSortOrderIfNeeded()
                refreshPendingCount()
            }
            .onAppear {
                if openShoppingCartFromToday {
                    openShoppingCartFromToday = false
                    showShoppingCart = true
                }
            }
            .onChange(of: logs.count) { _, _ in
                refreshPendingCount()
            }
            .onChange(of: medications.count) { _, _ in
                refreshPendingCount()
            }
            .onChange(of: openShoppingCartFromToday) { _, newValue in
                if newValue {
                    openShoppingCartFromToday = false
                    showShoppingCart = true
                }
            }
            .sheet(item: $addMode) { mode in
                EditMedicationView(medication: nil, creationKind: mode.kind)
            }
            .sheet(item: $editMed) { med in
                EditMedicationView(medication: med)
            }
            .sheet(isPresented: $showShoppingCart) {
                NavigationStack {
                    ShoppingCartView()
                }
            }
            .alert(L10n.tr("cart_disclaimer_title"), isPresented: $showShoppingDisclaimerAlert) {
                Button(L10n.tr("cart_disclaimer_understood")) {
                    shoppingCartDisclaimerShown = true
                    runPendingCartAction()
                }
            } message: {
                Text(L10n.tr("cart_disclaimer_message"))
            }
        }
    }

    private var medicationsList: some View {
        List {
            if medications.isEmpty {
                EmptyMedicinesStateView()
                    .listRowBackground(Color.clear)
            } else {
                scheduledSection
                occasionalSection
            }
        }
        .safeAreaPadding(.bottom, 84)
        .environment(\.editMode, $listEditMode)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
    }

    private var scheduledSection: some View {
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
    }

    private var occasionalSection: some View {
        Section {
            ForEach(occasionalGroups) { group in
                medicationRow(group.representative)
            }
            .onDelete(perform: deleteOccasionalGroups)
            .onMove(perform: moveOccasionalGroups)
        } header: {
            Text(L10n.tr("medications_section_occasional"))
                .foregroundStyle(AppTheme.brandYellow)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            NavigationTitleWithIcon(
                title: L10n.tr("medications_title"),
                systemImage: "pills",
                color: AppTheme.brandYellow
            )
        }
        ToolbarItemGroup(placement: .topBarLeading) {
            Button {
                withAnimation {
                    listEditMode = (listEditMode == .active) ? .inactive : .active
                }
            } label: {
                Image(systemName: (listEditMode == .active) ? "checkmark" : "pencil")
            }
            .foregroundStyle(AppTheme.brandYellow)
            .accessibilityLabel(L10n.tr("button_edit"))

            Button {
                selectedTab = .noTaken
            } label: {
                PendingIntakesIconView(count: pendingCount)
            }
            .foregroundStyle(AppTheme.brandYellow)
            .accessibilityLabel(L10n.tr("tab_not_taken"))
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button {
                requestCartOpen()
            } label: {
                ShoppingCartIconView(count: shoppingCartCount)
            }
            .foregroundStyle(AppTheme.brandYellow)

            Button { showingAddTypeDialog = true } label: { Image(systemName: "plus") }
                .foregroundStyle(AppTheme.brandYellow)
        }
    }

    private var shoppingCartCount: Int {
        medications.filter { $0.inShoppingCart }.count
    }

    private func refreshPendingCount() {
        pendingCount = PendingIntakeService.pendingMedicationCount(
            medications: medications,
            logs: logs
        )
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

    private var occasionalGroups: [OccasionalGroup] {
        let grouped = Dictionary(grouping: occasionalMeds) { normalizedMedicationName($0.name) }
        var groups: [OccasionalGroup] = []
        groups.reserveCapacity(grouped.count)

        for meds in grouped.values {
            let ordered = meds.sorted {
                let a = $0.sortOrder ?? 0
                let b = $1.sortOrder ?? 0
                if a != b { return a < b }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            guard let first = ordered.first else { continue }
            let representative = meds.max { lhs, rhs in
                (lhs.startDateRaw ?? .distantPast) < (rhs.startDateRaw ?? .distantPast)
            } ?? first

            groups.append(
                OccasionalGroup(
                    id: normalizedMedicationName(first.name),
                    medications: ordered,
                    representative: representative
                )
            )
        }

        groups.sort { lhs, rhs in
            let lo = lhs.medications.first?.sortOrder ?? 0
            let ro = rhs.medications.first?.sortOrder ?? 0
            if lo != ro { return lo < ro }
            return lhs.representative.name.localizedCaseInsensitiveCompare(rhs.representative.name) == .orderedAscending
        }
        return groups
    }

    @ViewBuilder
    private func medicationRow(_ med: Medication) -> some View {
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

            Spacer(minLength: 8)

            Button {
                requestToggleCart(medicationID: med.id)
            } label: {
                Image(systemName: med.inShoppingCart ? "cart.fill" : "cart.badge.plus")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(AppTheme.brandYellow)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 6)
        .opacity(med.isActive ? 1 : 0.55)
        .contentShape(Rectangle())
        .onTapGesture {
            editMed = med
        }
    }

    private func requestCartOpen() {
        if shoppingCartDisclaimerShown {
            showShoppingCart = true
            return
        }
        pendingOpenCart = true
        pendingCartMedicationID = nil
        showShoppingDisclaimerAlert = true
    }

    private func requestToggleCart(medicationID: UUID) {
        guard let med = medications.first(where: { $0.id == medicationID }) else { return }
        if med.inShoppingCart {
            med.inShoppingCart = false
            med.shoppingCartRemainingDoses = nil
            med.shoppingCartSortOrder = nil
            try? modelContext.save()
            return
        }

        if shoppingCartDisclaimerShown {
            addToCart(medicationID: medicationID)
            return
        }
        pendingCartMedicationID = medicationID
        pendingOpenCart = false
        showShoppingDisclaimerAlert = true
    }

    private func addToCart(medicationID: UUID) {
        guard let med = medications.first(where: { $0.id == medicationID }) else { return }
        med.inShoppingCart = true
        if med.shoppingCartSortOrder == nil {
            med.shoppingCartSortOrder = nextCartSortOrder
        }
        try? modelContext.save()
    }

    private var nextCartSortOrder: Int {
        (medications.compactMap { $0.shoppingCartSortOrder }.max() ?? -1) + 1
    }

    private func runPendingCartAction() {
        if pendingOpenCart {
            showShoppingCart = true
        } else if let medicationID = pendingCartMedicationID {
            addToCart(medicationID: medicationID)
        }
        clearPendingCartAction()
    }

    private func clearPendingCartAction() {
        pendingOpenCart = false
        pendingCartMedicationID = nil
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
    }

    private func move(from source: IndexSet, to destination: Int, in section: SectionKind) {
        var scheduled = scheduledMeds
        switch section {
        case .scheduled:
            scheduled.move(fromOffsets: source, toOffset: destination)
        }

        let current = scheduled + occasionalMeds
        for (idx, med) in current.enumerated() {
            med.sortOrder = idx
        }
        try? modelContext.save()
    }

    private func moveOccasionalGroups(from source: IndexSet, to destination: Int) {
        var groups = occasionalGroups
        groups.move(fromOffsets: source, toOffset: destination)

        var currentOrder = scheduledMeds.count
        for group in groups {
            for med in group.medications {
                med.sortOrder = currentOrder
                currentOrder += 1
            }
        }
        try? modelContext.save()
    }

    private func deleteOccasionalGroups(_ indexSet: IndexSet) {
        for i in indexSet {
            let group = occasionalGroups[i]
            for med in group.medications {
                NotificationService.cancelOccasionalReminder(medicationID: med.id)
                modelContext.delete(med)
            }
        }
        try? modelContext.save()
        normalizeSortOrderIfNeeded(force: true)
    }

    private func normalizedMedicationName(_ name: String) -> String {
        name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
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
        if !med.isActive && !med.hasConfiguredStartDate {
            Text(med.kind == .occasional ? L10n.tr("summary_no_date") : L10n.tr("summary_no_schedule"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else if med.kind == .occasional {
            Text(occasionalSummaryText(for: med))
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

    private func occasionalSummaryText(for med: Medication) -> String {
        let dateText = String(format: L10n.tr("summary_occasional_date_line_format"), Fmt.dayMedium(med.startDate))
        guard let takenAt = occasionalTakenTime(for: med) else {
            return dateText
        }
        return "\(dateText) · \(Fmt.timeShort(takenAt))"
    }

    private func occasionalTakenTime(for med: Medication) -> Date? {
        let cal = Calendar.current
        let dayKey = cal.startOfDay(for: med.startDate)
        return logs.first(where: { $0.medicationID == med.id && cal.isDate($0.dateKey, inSameDayAs: dayKey) })?.takenAt
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
