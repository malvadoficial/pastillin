import SwiftUI
import SwiftData

enum DayStatus {
    case none       // blanco: no tocaba nada
    case allTaken   // verde
    case someTaken  // amarillo
    case noneTaken  // rojo
}

struct CalendarView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Query private var medications: [Medication]
    @Query private var logs: [IntakeLog]
    @Query private var intakes: [Intake]
    @AppStorage("selectedTab") private var selectedTab: AppTab = .calendar
    @AppStorage("lastTabBeforeNoTaken") private var lastTabBeforeNoTakenRaw: String = AppTab.calendar.rawValue
    @AppStorage("shoppingCartDisclaimerShown") private var shoppingCartDisclaimerShown: Bool = false

    @State private var monthBase: Date = Date()
    @State private var selectedDay: Date? = nil
    @State private var selectedLogDetail: SelectedLogWrapper? = nil
    @State private var dayEditorTarget: DayEditorWrapper? = nil
    @State private var addIntakeTarget: AddIntakeWrapper? = nil
    @State private var showShoppingDisclaimerAlert = false
    @State private var pendingCount: Int = 0
    @State private var calendarRefreshTick: Int = 0
    private var isCompactLayout: Bool { verticalSizeClass == .compact }
    private var rootSpacing: CGFloat { isCompactLayout ? 4 : 8 }
    private var gridSpacing: CGFloat { isCompactLayout ? 4 : 8 }
    private var dayCellMinHeight: CGFloat { isCompactLayout ? 30 : 56 }
    private var dayFont: Font { isCompactLayout ? .caption : .subheadline }
    private var statusDotSize: CGFloat { isCompactLayout ? 6 : 9 }
    private var monthTitleFont: Font { isCompactLayout ? .headline : .title3.weight(.semibold) }
    private var monthHeaderHorizontalPadding: CGFloat { isCompactLayout ? 10 : 16 }
    private var weekdayFont: Font { isCompactLayout ? .caption2.weight(.semibold) : .caption.weight(.semibold) }
    private var selectedDayHasRows: Bool {
        guard let selectedDay else { return false }
        let dayKey = Calendar.current.startOfDay(for: selectedDay)
        return !rowsForDay(dayKey).isEmpty
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: rootSpacing) {
                    header

                    let cells = monthGridCells(for: monthBase)
                    let columns = Array(repeating: GridItem(.flexible(), spacing: gridSpacing), count: 7)

                    weekdayHeader

                    LazyVGrid(columns: columns, spacing: gridSpacing) {
                        ForEach(cells) { cell in
                            if let day = cell.date {
                                let status = statusForDay(day)
                                let today = isToday(day)
                                let isSelected = selectedDay.map { Calendar.current.isDate($0, inSameDayAs: day) } ?? false

                                Button {
                                    let key = Calendar.current.startOfDay(for: day)
                                    selectedDay = key
                                    let today = Calendar.current.startOfDay(for: Date())
                                    if key >= today {
                                        try? LogService.ensureLogs(for: key, modelContext: modelContext)
                                    }
                                } label: {
                                    VStack(spacing: 6) {
                                        Text("\(Calendar.current.component(.day, from: day))")
                                            .font(dayFont.weight(.semibold))
                                            .frame(maxWidth: .infinity)

                                        Circle()
                                            .frame(width: statusDotSize, height: statusDotSize)
                                            .foregroundStyle(color(for: status))
                                    }
                                    .frame(maxWidth: .infinity, minHeight: dayCellMinHeight)
                                    .padding(.vertical, isCompactLayout ? 1 : 3)
                                    .padding(.horizontal, 4)
                                    .background(dayCellBackground(isSelected: isSelected, isToday: today))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(
                                                isSelected ? AppTheme.brandBlue : (today ? AppTheme.brandRed : Color.clear),
                                                lineWidth: isSelected ? 2 : (today ? 2 : 0)
                                            )
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                                .buttonStyle(.plain)
                            } else {
                                Color.clear
                                    .frame(maxWidth: .infinity, minHeight: dayCellMinHeight)
                                    .padding(.vertical, isCompactLayout ? 1 : 3)
                                    .padding(.horizontal, 4)
                            }
                        }
                    }
                    .id(calendarRefreshTick)
                    .padding(.horizontal, isCompactLayout ? 8 : 12)

                    if let day = selectedDay {
                        compactListForSelectedDay(day)
                            .padding(.top, isCompactLayout ? 6 : 10)
                    }
                }
            }
            .textSelection(.enabled)
            .safeAreaPadding(.bottom, 84)
            .padding(.bottom, isCompactLayout ? 6 : 0)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !isCompactLayout {
                    ToolbarItem(placement: .principal) {
                        NavigationTitleWithIcon(
                            title: L10n.tr("calendar_title"),
                            systemImage: "calendar",
                            color: AppTheme.brandRed
                        )
                    }
                }
                ToolbarItemGroup(placement: .topBarLeading) {
                    if selectedDayHasRows {
                        Button {
                            let target = selectedDay ?? Calendar.current.startOfDay(for: Date())
                            dayEditorTarget = DayEditorWrapper(date: target)
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .foregroundStyle(AppTheme.brandRed)
                        .accessibilityLabel(L10n.tr("button_edit"))
                    }

                    Button {
                        lastTabBeforeNoTakenRaw = AppTab.calendar.rawValue
                        selectedTab = .noTaken
                    } label: {
                        PendingIntakesIconView(count: pendingCount)
                    }
                    .foregroundStyle(AppTheme.brandRed)
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
                    .foregroundStyle(AppTheme.brandRed)

                    Button {
                        let target = Calendar.current.startOfDay(for: selectedDay ?? Date())
                        addIntakeTarget = AddIntakeWrapper(day: target)
                    } label: {
                        Image(systemName: "plus")
                    }
                    .foregroundStyle(AppTheme.brandRed)
                }
            }
            .sheet(item: $selectedLogDetail) { wrap in
                MedicationLogDetailView(
                    medication: wrap.med,
                    dayKey: wrap.dayKey,
                    log: wrap.log
                )
            }
            .sheet(item: $dayEditorTarget) { wrap in
                DayDetailView(day: wrap.date)
            }
            .sheet(item: $addIntakeTarget) { wrap in
                AddIntakePickerView(
                    day: wrap.day,
                    medications: medications.filter { $0.isActive }
                ) { medication, option in
                    createManualIntake(for: medication, day: wrap.day, option: option)
                    addIntakeTarget = nil
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
            .onAppear {
                try? IntakeSchedulingService.bootstrapScheduledIntakes(modelContext: modelContext)
                ensureVisibleMonthLogs()
                if selectedDay == nil {
                    selectedDay = Calendar.current.startOfDay(for: Date())
                }
                refreshPendingCount()
            }
            .onChange(of: monthBase) { _, _ in
                ensureVisibleMonthLogs()
            }
            .onChange(of: selectedDay) { _, newValue in
                if let d = newValue {
                    ensureLogsForIntakes(on: d)
                }
            }
            .onChange(of: logs.count) { _, _ in
                refreshPendingCount()
                calendarRefreshTick &+= 1
            }
            .onChange(of: intakes.count) { _, _ in
                ensureVisibleMonthLogs()
                calendarRefreshTick &+= 1
            }
            .onChange(of: medications.count) { _, _ in
                try? IntakeSchedulingService.bootstrapScheduledIntakes(modelContext: modelContext)
                ensureVisibleMonthLogs()
                refreshPendingCount()
                calendarRefreshTick &+= 1
            }
            .onChange(of: selectedLogDetail?.id) { _, newValue in
                if newValue == nil {
                    refreshPendingCount()
                    calendarRefreshTick &+= 1
                }
            }
            .onChange(of: dayEditorTarget?.id) { _, newValue in
                if newValue == nil {
                    refreshPendingCount()
                    calendarRefreshTick &+= 1
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .calendarJumpToToday)) { _ in
                monthBase = Date()
                let today = Calendar.current.startOfDay(for: Date())
                selectedDay = today
                ensureLogsForIntakes(on: today)
                refreshPendingCount()
            }
            .onReceive(NotificationCenter.default.publisher(for: .intakeLogsDidChange)) { _ in
                refreshPendingCount()
                calendarRefreshTick &+= 1
            }
        }
    }

    private var shoppingCartCount: Int {
        medications.filter { $0.inShoppingCart }.count
    }

    private func refreshPendingCount() {
        let fetchedMeds = (try? modelContext.fetch(FetchDescriptor<Medication>())) ?? medications
        let fetchedLogs = (try? modelContext.fetch(FetchDescriptor<IntakeLog>())) ?? logs
        pendingCount = PendingIntakeService.pendingMedicationCount(
            medications: fetchedMeds,
            logs: fetchedLogs
        )
    }

    private func ensureVisibleMonthLogs() {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: monthBase)
        guard let firstOfMonth = cal.date(from: comps) else { return }
        guard let dayRange = cal.range(of: .day, in: .month, for: firstOfMonth) else { return }
        guard let lastOfMonth = cal.date(byAdding: .day, value: dayRange.count - 1, to: firstOfMonth) else { return }
        let from = cal.startOfDay(for: firstOfMonth)
        let to = cal.startOfDay(for: lastOfMonth)
        ensureLogsForIntakes(from: from, to: to)
    }

    private func createManualIntake(for medication: Medication, day: Date, option: IntakeAddOption) {
        let calendar = Calendar.current
        let dayKey = calendar.startOfDay(for: day)

        if option == .startSchedule, medication.kind == .scheduled {
            medication.startDate = dayKey
            medication.setSkipped(false, on: dayKey)
            try? IntakeSchedulingService.regenerateFutureIntakes(
                for: medication,
                from: dayKey,
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

    private func ensureLogsForIntakes(on day: Date) {
        let key = Calendar.current.startOfDay(for: day)
        ensureLogsForIntakes(from: key, to: key)
    }

    private func ensureLogsForIntakes(from start: Date, to end: Date) {
        let calendar = Calendar.current
        let startKey = calendar.startOfDay(for: min(start, end))
        let endKey = calendar.startOfDay(for: max(start, end))

        let intakesInRange = intakes.filter { intake in
            let key = calendar.startOfDay(for: intake.scheduledAt)
            return key >= startKey && key <= endKey
        }
        guard !intakesInRange.isEmpty else { return }

        let existingLogKeys = Set(logs.compactMap { log -> String? in
            guard let intakeID = log.intakeID else { return nil }
            return "\(intakeID.uuidString)-\(calendar.startOfDay(for: log.dateKey).timeIntervalSinceReferenceDate)"
        })

        var inserted = false
        for intake in intakesInRange {
            let dayKey = calendar.startOfDay(for: intake.scheduledAt)
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

    private var header: some View {
        HStack {
            Button { monthBase = addMonths(monthBase, -1) } label: { Image(systemName: "chevron.left") }
                .foregroundStyle(AppTheme.brandRed)
            Spacer()
            Text(Fmt.monthTitle(monthBase))
                .font(monthTitleFont)
                .foregroundStyle(AppTheme.brandRed)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer()
            Button { monthBase = addMonths(monthBase, 1) } label: { Image(systemName: "chevron.right") }
                .foregroundStyle(AppTheme.brandRed)
        }
        .padding(.top, isCompactLayout ? 2 : 4)
        .padding(.horizontal, monthHeaderHorizontalPadding)
    }

    private var weekdayHeader: some View {
        let symbols = weekdaySymbolsStartingMonday()
        return HStack(spacing: 8) {
            ForEach(symbols, id: \.self) { s in
                Text(s)
                    .font(weekdayFont)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal)
    }

    private func weekdaySymbolsStartingMonday() -> [String] {
        let f = DateFormatter()
        f.locale = Locale.autoupdatingCurrent
        // 7 símbolos, empezando por lunes
        let symbols = f.veryShortStandaloneWeekdaySymbols ?? f.shortStandaloneWeekdaySymbols ?? []
        if symbols.count == 7 {
            // En DateFormatter, el índice 0 suele ser domingo. Queremos lunes primero.
            return Array(symbols[1...]) + [symbols[0]]
        }
        return symbols
    }

    // MARK: - Day status logic (🟥⬜🟩🟨)

    private func statusForDay(_ day: Date) -> DayStatus {
        let cal = Calendar.current
        let key = cal.startOfDay(for: day)
        let rows = rowsForDay(key)
        if rows.isEmpty { return .none }
        let takenCount = rows.filter { $0.log.isTaken }.count
        if takenCount == 0 { return .noneTaken }
        if takenCount == rows.count { return .allTaken }
        return .someTaken
    }

    private func color(for status: DayStatus) -> Color {
        switch status {
        case .none: return .white
        case .allTaken: return AppTheme.brandBlue
        case .someTaken: return AppTheme.brandYellow
        case .noneTaken: return AppTheme.brandRed
        }
    }

    private func isToday(_ day: Date) -> Bool {
        Calendar.current.isDateInToday(day)
    }

    @ViewBuilder
    private func dayCellBackground(isSelected: Bool, isToday: Bool) -> some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 12)
                .fill(AppTheme.brandBlue.opacity(0.24))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.thinMaterial.opacity(0.35))
                }
        } else if isToday {
            RoundedRectangle(cornerRadius: 12)
                .fill(AppTheme.brandRed.opacity(0.18))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.thinMaterial.opacity(0.3))
                }
        } else {
            RoundedRectangle(cornerRadius: 12)
                .fill(.thinMaterial)
        }
    }

    // MARK: - Month grid helpers

    private func monthGridCells(for base: Date) -> [MonthGridCell] {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: base)
        let first = cal.date(from: comps)!
        let range = cal.range(of: .day, in: .month, for: first)!

        // weekday: 1=domingo ... 7=sábado. Convertimos a índice empezando en lunes (0...6).
        let weekday = cal.component(.weekday, from: first)
        let leadingBlanks = (weekday + 5) % 7

        var cells: [MonthGridCell] = []
        cells.reserveCapacity(leadingBlanks + range.count)

        for index in 0..<leadingBlanks {
            cells.append(MonthGridCell(id: index, date: nil))
        }

        for day in range {
            if let date = cal.date(byAdding: .day, value: day - 1, to: first).map({ cal.startOfDay(for: $0) }) {
                cells.append(MonthGridCell(id: cells.count, date: date))
            }
        }
        return cells
    }

    private func addMonths(_ date: Date, _ delta: Int) -> Date {
        Calendar.current.date(byAdding: .month, value: delta, to: date) ?? date
    }

    @ViewBuilder
    private func compactListForSelectedDay(_ day: Date) -> some View {
        let dayKey = Calendar.current.startOfDay(for: day)
        let items = rowsForDay(dayKey)

        VStack(alignment: .leading, spacing: 6) {
            Text(Fmt.dayLong(dayKey))
                .font(isCompactLayout ? .caption.weight(.bold) : .subheadline.weight(.bold))
                .foregroundStyle(AppTheme.brandRed)
                .frame(maxWidth: .infinity, alignment: .center)

            if items.isEmpty {
                EmptyMedicinesStateView()
                    .frame(maxWidth: .infinity)
            } else {
                LazyVStack(spacing: 6) {
                    ForEach(items) { item in
                        Button {
                            selectedLogDetail = SelectedLogWrapper(med: item.med, log: item.log, dayKey: dayKey)
                        } label: {
                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                                        Text(item.med.name)
                                            .font(.footnote.weight(.semibold))

                                        if item.med.kind == .occasional {
                                            Text(L10n.tr("medication_occasional_badge_short"))
                                                .font(.caption2.weight(.semibold))
                                                .foregroundStyle(AppTheme.brandBlue)
                                        }
                                    }

                                    Text(item.log.isTaken ? (item.log.takenAt.map { Fmt.timeShort($0) } ?? L10n.tr("time_unspecified")) : "—")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Text(item.log.isTaken ? L10n.tr("status_taken_masc") : L10n.tr("status_not_taken_masc"))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(item.log.isTaken ? AppTheme.brandBlue : .secondary)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(.thinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, isCompactLayout ? 8 : 10)
    }

    private func rowsForDay(_ dayKey: Date) -> [CalendarRow] {
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
                return CalendarRow(id: intake.id, med: med, log: log)
            }
        }

        // Fallback legado para datos antiguos sin tomas persistidas.
        let uniqueMedicationIDs = Set(dayLogs.map(\.medicationID))
        let medsToShow = uniqueMedicationIDs.compactMap { medsByID[$0] }.sorted {
            let o0 = $0.sortOrder ?? 0
            let o1 = $1.sortOrder ?? 0
            if o0 != o1 { return o0 < o1 }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }

        return medsToShow.compactMap { med in
            guard let log = dayLogs.first(where: { $0.medicationID == med.id }) else { return nil }
            return CalendarRow(id: log.id, med: med, log: log)
        }
    }

    struct CalendarRow: Identifiable {
        let id: UUID
        let med: Medication
        let log: IntakeLog
    }

    struct SelectedLogWrapper: Identifiable {
        let id = UUID()
        let med: Medication
        let log: IntakeLog
        let dayKey: Date
    }

    struct MonthGridCell: Identifiable {
        let id: Int
        let date: Date?
    }

    struct DayEditorWrapper: Identifiable {
        let id = UUID()
        let date: Date
    }

    struct AddIntakeWrapper: Identifiable {
        let id = UUID()
        let day: Date
    }
}

private struct AddIntakePickerView: View {
    @Environment(\.dismiss) private var dismiss
    let day: Date
    let medications: [Medication]
    let onSelect: (Medication, IntakeAddOption) -> Void
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
                    ForEach(IntakeAddOption.options(for: medication.kind), id: \.self) { option in
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

private enum IntakeAddOption: Hashable {
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

    static func options(for kind: MedicationKind) -> [IntakeAddOption] {
        switch kind {
        case .occasional:
            return [.occasionalTaken]
        case .scheduled:
            return [.occasionalTaken, .startSchedule]
        }
    }
}
