import SwiftUI
import SwiftData
import UIKit

struct TodayRow: Identifiable {
    let id: UUID
    let medication: Medication
    let log: IntakeLog
}

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var medications: [Medication]
    @Query private var logs: [IntakeLog]
    @Query private var intakes: [Intake]
    @AppStorage("selectedTab") private var selectedTab: AppTab = .today
    @AppStorage("lastTabBeforeNoTaken") private var lastTabBeforeNoTakenRaw: String = AppTab.today.rawValue
    @AppStorage("shoppingCartDisclaimerShown") private var shoppingCartDisclaimerShown: Bool = false

    @State private var rows: [TodayRow] = []
    @State private var showShoppingDisclaimerAlert = false
    @State private var selected: SelectedWrapper? = nil
    @State private var addIntakeTarget: AddTodayIntakeTarget? = nil
    @State private var showHelpFromGuide = false
    @State private var didDismissGettingStartedOverlay = false
    @State private var plusButtonFrame: CGRect = .zero
    @State private var helpButtonFrame: CGRect = .zero

    // Evita que el tap del botón dispare también el tap de la celda
    @State private var suppressCellTap = false
    
    private var isFirstRunOrCleanState: Bool {
        medications.isEmpty && logs.isEmpty
    }
    private var shouldShowGettingStartedOverlay: Bool {
        isFirstRunOrCleanState && rows.isEmpty && addIntakeTarget == nil && !didDismissGettingStartedOverlay
    }
    private var shoppingCartCount: Int {
        medications.filter { $0.inShoppingCart }.count
    }
    private var pendingCount: Int {
        PendingIntakeService.pendingMedicationCount(
            medications: medications,
            logs: logs
        )
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(Fmt.dayLong(Date()))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(AppTheme.brandBlue)
                        .frame(maxWidth: .infinity, alignment: .center)

                    if pendingCount > 0 {
                        Button {
                            lastTabBeforeNoTakenRaw = AppTab.today.rawValue
                            selectedTab = .noTaken
                        } label: {
                            Text(String(format: L10n.tr("today_pending_notice_format"), pendingCount))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppTheme.brandRed)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 2)
                        }
                        .buttonStyle(.plain)
                    }

                    if shoppingCartCount > 0 {
                        Button {
                            selectedTab = .cart
                        } label: {
                            Text(L10n.tr("today_shopping_notice"))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppTheme.brandYellow)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 2)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if rows.isEmpty {
                    EmptyMedicinesStateView()
                    if isFirstRunOrCleanState {
                        HStack {
                            Spacer()
                            NavigationLink {
                                HelpView()
                            } label: {
                                Label(L10n.tr("today_open_help"), systemImage: "questionmark.circle")
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(AppTheme.brandBlue)
                            .background(
                                GeometryReader { proxy in
                                    Color.clear.preference(
                                        key: HelpButtonFramePreferenceKey.self,
                                        value: proxy.frame(in: .named("today-root"))
                                    )
                                }
                            )
                            Spacer()
                        }
                        .padding(.vertical, 8)
                    }
                } else {
                    ForEach(rows) { row in
                        HStack(spacing: 12) {
                            medicationThumbnail(for: row.medication)

                            // Nombre + hora
                            VStack(alignment: .leading, spacing: 4) {
                                Text(row.medication.name)
                                    .font(.subheadline.weight(.semibold))

                                if row.medication.kind == .occasional {
                                    Text(L10n.tr("medication_occasional_badge_short"))
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(AppTheme.brandBlue)
                                }

                                if row.log.isTaken {
                                    Text(row.log.takenAt.map { Fmt.timeShort($0) } ?? L10n.tr("time_unspecified"))
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("—")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }

                                if row.medication.inShoppingCart {
                                    if let runOutDate = row.medication.estimatedRunOutDate() {
                                        Text(String(format: L10n.tr("today_cart_runs_out_format"), Fmt.dayMedium(runOutDate)))
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(AppTheme.brandYellow)
                                    } else {
                                        Text(L10n.tr("today_cart_pending_purchase"))
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(AppTheme.brandYellow)
                                    }
                                }
                            }

                            Spacer()

                            // Botón único (toggle)
                            Button {
                                toggleTaken(for: row.log)
                            } label: {
                                Text(row.log.isTaken ? L10n.tr("taken_fem") : L10n.tr("not_taken_fem"))
                                    .font(.footnote.weight(.semibold))
                                    .frame(width: 88, height: 28)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(row.log.isTaken ? AppTheme.brandBlue : AppTheme.brandRed)

                        }
                        .padding(.vertical, 6)
                        // Celda entera tappable para abrir detalle
                        .contentShape(Rectangle())
                        .onTapGesture {
                            guard !suppressCellTap else { return }
                            let key = Calendar.current.startOfDay(for: Date())
                            selected = SelectedWrapper(med: row.medication, log: row.log, dayKey: key)
                        }
                    }
                }
            }
            .textSelection(.enabled)
            .safeAreaPadding(.bottom, 84)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    NavigationTitleWithIcon(
                        title: L10n.tr("today_title"),
                        systemImage: "checklist",
                        color: AppTheme.brandBlue
                    )
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        lastTabBeforeNoTakenRaw = AppTab.today.rawValue
                        selectedTab = .noTaken
                    } label: {
                        PendingIntakesIconView(count: pendingCount)
                    }
                    .foregroundStyle(AppTheme.brandBlue)
                    .accessibilityLabel(L10n.tr("tab_not_taken"))
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        if shoppingCartDisclaimerShown {
                            selectedTab = .cart
                        } else {
                            showShoppingDisclaimerAlert = true
                        }
                    } label: {
                        ShoppingCartIconView(count: shoppingCartCount)
                    }
                    .foregroundStyle(AppTheme.brandBlue)

                    Button {
                        addIntakeTarget = AddTodayIntakeTarget(day: Calendar.current.startOfDay(for: Date()))
                    } label: {
                        ZStack {
                            Circle()
                                .fill(AppTheme.brandBlue)
                                .frame(width: 28, height: 28)
                            Image(systemName: "plus")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: PlusButtonFramePreferenceKey.self,
                                value: proxy.frame(in: .named("today-root"))
                            )
                        }
                    )
                }
            }
            .overlay {
                if shouldShowGettingStartedOverlay {
                    TodayGettingStartedOverlay(
                        plusFrame: plusButtonFrame,
                        helpFrame: helpButtonFrame,
                        onTapPlus: { addIntakeTarget = AddTodayIntakeTarget(day: Calendar.current.startOfDay(for: Date())) },
                        onTapHelp: {
                            didDismissGettingStartedOverlay = true
                            showHelpFromGuide = true
                        }
                    )
                    .transition(.opacity)
                    .zIndex(3)
                }
            }
            .coordinateSpace(name: "today-root")
            .onPreferenceChange(PlusButtonFramePreferenceKey.self) { frame in
                plusButtonFrame = frame
            }
            .onPreferenceChange(HelpButtonFramePreferenceKey.self) { frame in
                helpButtonFrame = frame
            }
            .onAppear {
                try? IntakeSchedulingService.bootstrapScheduledIntakes(modelContext: modelContext)
                ensureLogsForIntakesToday()
                normalizeSortOrderIfNeeded()
                reload()
            }
            .onChange(of: medications.count) { _, _ in
                try? IntakeSchedulingService.bootstrapScheduledIntakes(modelContext: modelContext)
                ensureLogsForIntakesToday()
                reload()
            }
            .onChange(of: logs.count) { _, _ in
                reload()
            }
            .onChange(of: intakes.count) { _, _ in
                ensureLogsForIntakesToday()
                reload()
            }
            .sheet(item: $selected) { wrap in
                MedicationLogDetailView(
                    medication: wrap.med,
                    dayKey: wrap.dayKey,
                    log: wrap.log
                )
            }
            .sheet(item: $addIntakeTarget) { target in
                TodayAddIntakePickerView(
                    day: target.day,
                    medications: medications.filter { $0.isActive }
                ) { medication, option in
                    createTodayIntake(for: medication, option: option, day: target.day)
                    addIntakeTarget = nil
                }
            }
            .sheet(isPresented: $showHelpFromGuide) {
                NavigationStack {
                    HelpView()
                        .safeAreaInset(edge: .bottom) {
                            Button(L10n.tr("button_close")) {
                                showHelpFromGuide = false
                            }
                            .buttonStyle(.borderedProminent)
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                            .padding(.bottom, 10)
                            .frame(maxWidth: .infinity)
                            .background(.ultraThinMaterial)
                        }
                }
            }
            .alert(L10n.tr("cart_disclaimer_title"), isPresented: $showShoppingDisclaimerAlert) {
                Button(L10n.tr("cart_disclaimer_understood")) {
                    shoppingCartDisclaimerShown = true
                    selectedTab = .cart
                }
            } message: {
                Text(L10n.tr("cart_disclaimer_message"))
            }
        }
    }

    // MARK: - Actions

    private func toggleTaken(for log: IntakeLog) {
        suppressCellTap = true
        defer {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                suppressCellTap = false
            }
        }

        _ = Calendar.current

        if log.isTaken {
            // Pasar a No tomado
            LogService.setTaken(false, for: log)
        } else {
            // Pasar a Tomado (hoy = hora real)
            LogService.setTaken(true, for: log, overrideTakenAt: nil)
        }

        try? modelContext.save()
        reload()
    }

    // MARK: - Data


    private func normalizeSortOrderIfNeeded() {
        let hasNil = medications.contains { $0.sortOrder == nil }
        let hasNonZero = medications.contains { ($0.sortOrder ?? 0) != 0 }
        if !hasNil && hasNonZero {
            return
        }
        let ordered = medications.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        for (idx, med) in ordered.enumerated() {
            med.sortOrder = idx
        }
        try? modelContext.save()
    }

    private func reload() {
        let cal = Calendar.current
        let key = cal.startOfDay(for: Date())
        let todayIntakes = intakes.filter { cal.isDate($0.scheduledAt, inSameDayAs: key) }
        let todayLogs = logs.filter { cal.isDate($0.dateKey, inSameDayAs: key) }
        let medsByID = Dictionary(uniqueKeysWithValues: medications.map { ($0.id, $0) })

        var temp: [TodayRow] = []
        let sortedIntakes = todayIntakes.sorted { lhs, rhs in
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

        for intake in sortedIntakes {
            guard let med = medsByID[intake.medicationID] else { continue }
            guard let log = todayLogs.first(where: { $0.intakeID == intake.id })
                ?? todayLogs.first(where: { $0.medicationID == med.id }) else { continue }
            temp.append(TodayRow(id: intake.id, medication: med, log: log))
        }
        rows = temp
    }

    private func ensureLogsForIntakesToday() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let todayIntakes = intakes.filter { cal.isDate($0.scheduledAt, inSameDayAs: today) }
        guard !todayIntakes.isEmpty else { return }

        let existingLogKeys = Set(logs.compactMap { log -> String? in
            guard let intakeID = log.intakeID else { return nil }
            return "\(intakeID.uuidString)-\(cal.startOfDay(for: log.dateKey).timeIntervalSinceReferenceDate)"
        })

        var inserted = false
        for intake in todayIntakes {
            let key = "\(intake.id.uuidString)-\(today.timeIntervalSinceReferenceDate)"
            if existingLogKeys.contains(key) { continue }
            modelContext.insert(
                IntakeLog(
                    medicationID: intake.medicationID,
                    intakeID: intake.id,
                    dateKey: today,
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

    private func createTodayIntake(for medication: Medication, option: TodayIntakeAddOption, day: Date) {
        let cal = Calendar.current
        let dayKey = cal.startOfDay(for: day)

        if option == .startSchedule, medication.kind == .scheduled {
            medication.startDate = dayKey
            medication.setSkipped(false, on: dayKey)
            try? IntakeSchedulingService.regenerateFutureIntakes(
                for: medication,
                from: dayKey,
                modelContext: modelContext
            )
            ensureLogsForIntakesToday()
            reload()
            return
        }

        let intake = Intake(
            medicationID: medication.id,
            scheduledAt: cal.date(bySettingHour: 12, minute: 0, second: 0, of: dayKey) ?? dayKey,
            source: option == .startSchedule ? .scheduled : .manual
        )
        modelContext.insert(intake)
        modelContext.insert(
            IntakeLog(
                medicationID: medication.id,
                intakeID: intake.id,
                dateKey: dayKey,
                isTaken: option == .occasionalTaken,
                takenAt: option == .occasionalTaken ? (cal.isDateInToday(dayKey) ? Date() : nil) : nil
            )
        )
        try? modelContext.save()
        NotificationCenter.default.post(name: .intakeLogsDidChange, object: nil)
        reload()
    }

    @ViewBuilder
    private func medicationThumbnail(for medication: Medication) -> some View {
        if let data = medication.photoData,
           let ui = UIImage(data: data) {
            Image(uiImage: ui)
                .resizable()
                .scaledToFill()
                .frame(width: 44, height: 44)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            MedicationDefaultArtworkView(
                kind: MedicationDefaultArtwork.kind(for: medication),
                width: 44,
                height: 44,
                cornerRadius: 8
            )
        }
    }

    struct SelectedWrapper: Identifiable {
        let id = UUID()
        let med: Medication
        let log: IntakeLog
        let dayKey: Date
    }

    struct AddTodayIntakeTarget: Identifiable {
        let id = UUID()
        let day: Date
    }
}

private struct PlusButtonFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero {
            value = next
        }
    }
}

private struct HelpButtonFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero {
            value = next
        }
    }
}

private struct TodayGettingStartedOverlay: View {
    let plusFrame: CGRect
    let helpFrame: CGRect
    let onTapPlus: () -> Void
    let onTapHelp: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let safeWidth = max(finite(proxy.size.width, fallback: 320), 1)
            let safeHeight = max(finite(proxy.size.height, fallback: 640), 1)
            let safeSize = CGSize(width: safeWidth, height: safeHeight)
            let safeTop = finite(proxy.safeAreaInsets.top, fallback: 0)
            let plusTarget = sanitizedFrame(normalizedPlusFrame(in: safeSize, safeTop: safeTop), in: safeSize)
            let helpTarget = sanitizedFrame(normalizedHelpFrame(in: safeSize), in: safeSize)
            let plusHoleWidth = max(plusTarget.width + 12, 1)
            let plusHoleHeight = max(plusTarget.height + 10, 1)
            let helpHoleWidth = max(helpTarget.width + 34, 1)
            let helpHoleHeight = max(helpTarget.height + 18, 1)
            let plusHintWidth = max(min(220, max(safeWidth - 24, 1)), 1)
            let helpHintWidth = max(min(300, max(safeWidth - 24, 1)), 1)
            let plusHintX = clamp(plusTarget.midX + 70, lower: 110, upper: max(safeWidth - 110, 110))
            let plusHintY = min(safeHeight - 40, plusTarget.maxY + 46)
            let helpHintX = clamp(helpTarget.midX, lower: 1, upper: max(safeWidth - 1, 1))
            let helpHintY = max(26, helpTarget.minY - 34)

            ZStack {
                Color.black.opacity(0.70)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .frame(width: plusHoleWidth, height: plusHoleHeight)
                            .position(x: plusTarget.midX, y: plusTarget.midY)
                            .blendMode(.destinationOut)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .frame(width: helpHoleWidth, height: helpHoleHeight)
                            .position(x: helpTarget.midX, y: helpTarget.midY)
                            .blendMode(.destinationOut)
                    )
                    .compositingGroup()
                    .ignoresSafeArea()

                Button(action: onTapPlus) {
                    Color.clear
                        .frame(width: max(plusTarget.width, 34), height: max(plusTarget.height, 34))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .position(x: plusTarget.midX, y: plusTarget.midY)

                Button(action: onTapHelp) {
                    Color.clear
                        .frame(
                            width: max(max(helpTarget.width + 8, 140), 1),
                            height: max(max(helpTarget.height + 8, 40), 1)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .position(x: helpTarget.midX, y: helpTarget.midY)

                Text(L10n.tr("today_overlay_plus_hint"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .frame(width: plusHintWidth)
                    .position(x: plusHintX, y: plusHintY)

                Text(L10n.tr("today_overlay_help_hint"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .frame(width: helpHintWidth)
                    .position(x: helpHintX, y: helpHintY)
            }
        }
        .ignoresSafeArea()
    }

    private func normalizedPlusFrame(in size: CGSize, safeTop: CGFloat) -> CGRect {
        if plusFrame == .zero {
            return CGRect(x: size.width - 52, y: safeTop + 8, width: 32, height: 32)
        }
        return plusFrame
    }

    private func normalizedHelpFrame(in size: CGSize) -> CGRect {
        if helpFrame == .zero {
            return CGRect(x: (size.width - 180) / 2, y: size.height * 0.62, width: 180, height: 42)
        }
        return helpFrame
    }

    private func sanitizedFrame(_ frame: CGRect, in size: CGSize) -> CGRect {
        let safeWidth = max(finite(frame.width, fallback: 32), 1)
        let safeHeight = max(finite(frame.height, fallback: 32), 1)
        let maxX = max(size.width - safeWidth, 0)
        let maxY = max(size.height - safeHeight, 0)
        let safeX = clamp(finite(frame.origin.x, fallback: 0), lower: 0, upper: maxX)
        let safeY = clamp(finite(frame.origin.y, fallback: 0), lower: 0, upper: maxY)
        return CGRect(x: safeX, y: safeY, width: safeWidth, height: safeHeight)
    }

    private func finite(_ value: CGFloat, fallback: CGFloat) -> CGFloat {
        value.isFinite ? value : fallback
    }

    private func clamp(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
        min(max(value, lower), upper)
    }
}

private struct TodayAddIntakePickerView: View {
    @Environment(\.dismiss) private var dismiss
    let day: Date
    let medications: [Medication]
    let onSelect: (Medication, TodayIntakeAddOption) -> Void
    @State private var searchText = ""
    @State private var selectedMedication: Medication? = nil
    @State private var showTypeSelector = false

    private var filtered: [Medication] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return medications.sorted { ($0.sortOrder ?? 0) < ($1.sortOrder ?? 0) }
        }
        return medications
            .filter { $0.name.localizedCaseInsensitiveContains(query) }
            .sorted { ($0.sortOrder ?? 0) < ($1.sortOrder ?? 0) }
    }

    var body: some View {
        NavigationStack {
            List {
                if filtered.isEmpty {
                    Text(L10n.tr("medications_search_no_results"))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(filtered) { medication in
                        Button {
                            selectedMedication = medication
                            showTypeSelector = true
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(medication.name)
                                    .foregroundStyle(.primary)
                                Text(medication.kind == .scheduled ? L10n.tr("medications_section_scheduled") : L10n.tr("medications_section_occasional"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
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
            .confirmationDialog(
                L10n.tr("medication_add_type_title"),
                isPresented: $showTypeSelector,
                titleVisibility: .visible
            ) {
                if let medication = selectedMedication {
                    ForEach(TodayIntakeAddOption.options(for: medication.kind), id: \.self) { option in
                        Button(option.title) {
                            onSelect(medication, option)
                        }
                    }
                }
                Button(L10n.tr("button_cancel"), role: .cancel) {}
            }
        }
    }
}

private enum TodayIntakeAddOption: Hashable {
    case occasionalTaken
    case startSchedule

    var title: String {
        switch self {
        case .occasionalTaken:
            return "Toma ocasional (marcada)"
        case .startSchedule:
            return "Comienzo de pauta"
        }
    }

    static func options(for kind: MedicationKind) -> [TodayIntakeAddOption] {
        switch kind {
        case .occasional:
            return [.occasionalTaken]
        case .scheduled:
            return [.occasionalTaken, .startSchedule]
        }
    }
}
