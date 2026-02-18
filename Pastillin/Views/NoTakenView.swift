import SwiftUI
import SwiftData
import UIKit

private struct MissedIntakeRow: Identifiable {
    let id: UUID
    let medication: Medication
    let log: IntakeLog
}

private enum MissedRange: Int, CaseIterable, Identifiable {
    case days7 = 7
    case days30 = 30
    case days90 = 90
    case days180 = 180

    var id: Int { rawValue }

    var titleKey: String {
        switch self {
        case .days7: return "missed_range_7"
        case .days30: return "missed_range_30"
        case .days90: return "missed_range_90"
        case .days180: return "missed_range_180"
        }
    }
}

struct NoTakenView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var medications: [Medication]
    @Query private var logs: [IntakeLog]
    @AppStorage("shoppingCartDisclaimerShown") private var shoppingCartDisclaimerShown: Bool = false

    @State private var rows: [MissedIntakeRow] = []
    @State private var selectedRow: MissedIntakeRow? = nil
    @State private var pendingMoveRow: MissedIntakeRow? = nil
    @State private var pendingTakenDate: Date = Calendar.current.startOfDay(for: Date())
    @State private var selectedRange: MissedRange = .days30
    @State private var showShoppingCart = false
    @State private var showShoppingDisclaimerAlert = false
    private let emptyArtworkHeight: CGFloat = 180

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker(L10n.tr("missed_range_title"), selection: $selectedRange) {
                        ForEach(MissedRange.allCases) { value in
                            Text(L10n.tr(value.titleKey)).tag(value)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if rows.isEmpty {
                    Section {
                        VStack(spacing: 12) {
                            pendingEmptyStateArtwork

                            Text(L10n.tr("missed_empty"))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.vertical, 8)
                    }
                } else {
                    ForEach(rows) { row in
                        Button {
                            selectedRow = row
                        } label: {
                            HStack(spacing: 12) {
                                medicationThumbnail(for: row.medication)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(row.medication.name)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)

                                    Text(Fmt.dayLong(row.log.dateKey))
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .safeAreaPadding(.bottom, 84)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    NavigationTitleWithIcon(
                        title: L10n.tr("missed_title"),
                        systemImage: "exclamationmark.triangle.fill",
                        color: AppTheme.brandRed
                    )
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if shoppingCartDisclaimerShown {
                            showShoppingCart = true
                        } else {
                            showShoppingDisclaimerAlert = true
                        }
                    } label: {
                        ShoppingCartIconView(count: shoppingCartCount)
                    }
                }
            }
            .overlay {
                if let row = selectedRow {
                    MissedIntakeActionsOverlay(
                        medicationName: row.medication.name,
                        dayText: Fmt.dayLong(row.log.dateKey),
                        onTaken: { markTaken(row) },
                        onNotTaken: { markNotTaken(row) },
                        onTakenToday: {
                            pendingTakenDate = Calendar.current.startOfDay(for: Date())
                            pendingMoveRow = row
                            selectedRow = nil
                        },
                        showTakenOtherDayAction: isClosestPendingToToday(for: row),
                        onCancel: { selectedRow = nil }
                    )
                    .zIndex(2)
                }

                if pendingMoveRow != nil {
                    MissedTakenOnDateOverlay(
                        selectedDate: $pendingTakenDate,
                        minDate: pendingMoveMinDate,
                        maxDate: pendingMoveMaxDate,
                        onConfirm: {
                            if let row = pendingMoveRow {
                                markTakenTodayAndMoveFuture(row)
                            }
                        },
                        onCancel: { pendingMoveRow = nil }
                    )
                    .zIndex(3)
                }
            }
            .onAppear {
                refreshData()
            }
            .onChange(of: selectedRange) { _, _ in
                refreshData()
            }
            .onChange(of: logs.count) { _, _ in
                reloadRows()
            }
            .onChange(of: medications.count) { _, _ in
                reloadRows()
            }
            .sheet(isPresented: $showShoppingCart) {
                NavigationStack {
                    ShoppingCartView()
                }
            }
            .alert(L10n.tr("cart_disclaimer_title"), isPresented: $showShoppingDisclaimerAlert) {
                Button(L10n.tr("cart_disclaimer_understood")) {
                    shoppingCartDisclaimerShown = true
                    showShoppingCart = true
                }
            } message: {
                Text(L10n.tr("cart_disclaimer_message"))
            }
        }
    }

    private var shoppingCartCount: Int {
        medications.filter { $0.inShoppingCart }.count
    }

    @ViewBuilder
    private var pendingEmptyStateArtwork: some View {
        let localeCode = Locale.current.language.languageCode?.identifier.lowercased() ?? "es"
        let preferredAssetName = localeCode.hasPrefix("en") ? "PendingEmptyState_EN" : "PendingEmptyState_ES"

        if UIImage(named: preferredAssetName) != nil {
            Image(preferredAssetName)
                .resizable()
                .scaledToFit()
                .frame(height: emptyArtworkHeight)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        } else if UIImage(named: "PendingEmptyState") != nil {
            Image("PendingEmptyState")
                .resizable()
                .scaledToFit()
                .frame(height: emptyArtworkHeight)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        } else {
            MedicationDefaultArtworkView(
                kind: .red,
                width: nil,
                height: emptyArtworkHeight,
                cornerRadius: 14
            )
        }
    }

    private func refreshData() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let start = cal.date(byAdding: .day, value: -(selectedRange.rawValue - 1), to: today) ?? today

        try? LogService.ensureLogs(from: start, to: today, modelContext: modelContext)
        reloadRows()
    }

    private func reloadRows() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let start = cal.date(byAdding: .day, value: -(selectedRange.rawValue - 1), to: today) ?? today
        let medsByID = Dictionary(uniqueKeysWithValues: medications.map { ($0.id, $0) })

        let missedRows = logs.compactMap { log -> MissedIntakeRow? in
            let dayKey = cal.startOfDay(for: log.dateKey)
            guard dayKey < today else { return nil }
            guard dayKey >= start else { return nil }
            guard !log.isTaken else { return nil }
            guard let med = medsByID[log.medicationID] else { return nil }
            guard med.kind == .scheduled else { return nil }
            guard isEligibleMedication(med) else { return nil }

            return MissedIntakeRow(id: log.id, medication: med, log: log)
        }

        var latestPendingByMedication: [UUID: MissedIntakeRow] = [:]
        for row in missedRows {
            if let existing = latestPendingByMedication[row.medication.id] {
                if row.log.dateKey > existing.log.dateKey {
                    latestPendingByMedication[row.medication.id] = row
                }
            } else {
                latestPendingByMedication[row.medication.id] = row
            }
        }

        let filteredLatestPending = latestPendingByMedication.values.filter { row in
            let rowDay = cal.startOfDay(for: row.log.dateKey)
            return !logs.contains { candidate in
                guard candidate.medicationID == row.medication.id else { return false }
                guard candidate.isTaken else { return false }
                let candidateDay = cal.startOfDay(for: candidate.dateKey)
                return candidateDay > rowDay && candidateDay <= today
            }
        }

        rows = Array(filteredLatestPending).sorted {
            if $0.log.dateKey != $1.log.dateKey {
                return $0.log.dateKey > $1.log.dateKey
            }
            return $0.medication.name.localizedCaseInsensitiveCompare($1.medication.name) == .orderedAscending
        }
    }

    private func isEligibleMedication(_ medication: Medication) -> Bool {
        guard let configuredStartDate = medication.startDateRaw else {
            return false
        }

        guard medication.repeatUnit != .day || medication.interval > 1 else {
            return false
        }

        guard medication.kind == .scheduled else {
            return false
        }

        guard let endDate = medication.endDate else {
            return true
        }

        let cal = Calendar.current
        let startKey = cal.startOfDay(for: configuredStartDate)
        let endKey = cal.startOfDay(for: endDate)

        guard endKey > startKey else { return false }

        switch medication.repeatUnit {
        case .day:
            let diff = cal.dateComponents([.day], from: startKey, to: endKey).day ?? 0
            return diff >= medication.interval
        case .month:
            guard let next = cal.date(byAdding: .month, value: medication.interval, to: startKey) else { return false }
            return cal.startOfDay(for: next) <= endKey
        }
    }

    private func markTaken(_ row: MissedIntakeRow) {
        let isToday = Calendar.current.isDateInToday(row.log.dateKey)
        row.log.isTaken = true
        row.log.takenAt = isToday ? Date() : nil
        try? modelContext.save()
        selectedRow = nil
        pendingMoveRow = nil
        reloadRows()
    }

    private func markNotTaken(_ row: MissedIntakeRow) {
        LogService.setTaken(false, for: row.log)
        try? modelContext.save()
        selectedRow = nil
        pendingMoveRow = nil
        reloadRows()
    }

    private func markTakenTodayAndMoveFuture(_ row: MissedIntakeRow) {
        guard isClosestPendingToToday(for: row) else {
            selectedRow = nil
            pendingMoveRow = nil
            return
        }

        let cal = Calendar.current
        let chosenDate = cal.startOfDay(for: pendingTakenDate)
        let minDate = cal.startOfDay(for: row.log.dateKey)
        let maxDate = cal.startOfDay(for: Date())
        let clampedChosenDate = min(max(chosenDate, minDate), maxDate)

        let now = Date()
        row.log.isTaken = true
        row.log.takenAt = cal.isDateInToday(clampedChosenDate) ? now : nil
        try? LogService.moveFutureScheduleAfterTakenOnDate(
            medication: row.medication,
            selectedDay: row.log.dateKey,
            takenOnDay: clampedChosenDate,
            now: now,
            allLogs: logs,
            modelContext: modelContext
        )
        try? LogService.ensureLogs(for: now, modelContext: modelContext)

        selectedRow = nil
        pendingMoveRow = nil
        reloadRows()
    }

    private var pendingMoveMinDate: Date {
        guard let row = pendingMoveRow else { return Calendar.current.startOfDay(for: Date()) }
        return Calendar.current.startOfDay(for: row.log.dateKey)
    }

    private var pendingMoveMaxDate: Date {
        Calendar.current.startOfDay(for: Date())
    }

    private func isClosestPendingToToday(for row: MissedIntakeRow) -> Bool {
        let cal = Calendar.current
        let latestPendingForMedication = rows
            .filter { $0.medication.id == row.medication.id }
            .map { cal.startOfDay(for: $0.log.dateKey) }
            .max()

        guard let latestPendingForMedication else { return false }
        return cal.isDate(latestPendingForMedication, inSameDayAs: row.log.dateKey)
    }

    @ViewBuilder
    private func medicationThumbnail(for medication: Medication) -> some View {
        if let data = medication.photoData,
           let ui = UIImage(data: data) {
            Image(uiImage: ui)
                .resizable()
                .scaledToFill()
                .frame(width: 40, height: 40)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            MedicationDefaultArtworkView(
                kind: MedicationDefaultArtwork.kind(for: medication),
                width: 40,
                height: 40,
                cornerRadius: 8
            )
        }
    }
}

private struct MissedIntakeActionsOverlay: View {
    let medicationName: String
    let dayText: String
    let onTaken: () -> Void
    let onNotTaken: () -> Void
    let onTakenToday: () -> Void
    let showTakenOtherDayAction: Bool
    let onCancel: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.62)
                .ignoresSafeArea()
                .onTapGesture(perform: onCancel)

            VStack(spacing: 12) {
                Text(L10n.tr("missed_modal_title"))
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(String(format: L10n.tr("missed_modal_message_format"), medicationName, dayText))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button(action: onTaken) {
                    actionText("missed_action_taken")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)

                Button(action: onNotTaken) {
                    actionText("missed_action_not_taken")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)

                if showTakenOtherDayAction {
                    Button(action: onTakenToday) {
                        actionText("missed_action_taken_other_day")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                }

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

    private func actionText(_ key: String) -> Text {
        if let attributed = try? AttributedString(markdown: L10n.tr(key)) {
            return Text(attributed)
        }
        return Text(L10n.tr(key))
    }
}

private struct MissedTakenOnDateOverlay: View {
    @Binding var selectedDate: Date
    let minDate: Date
    let maxDate: Date
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.62)
                .ignoresSafeArea()
                .onTapGesture(perform: onCancel)

            VStack(spacing: 12) {
                Text(L10n.tr("missed_move_alert_title"))
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(L10n.tr("missed_move_alert_message"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                DatePicker(
                    "",
                    selection: $selectedDate,
                    in: minDate...maxDate,
                    displayedComponents: [.date]
                )
                .datePickerStyle(.graphical)
                .labelsHidden()

                Button(action: onConfirm) {
                    Text(L10n.tr("missed_move_alert_confirm"))
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
