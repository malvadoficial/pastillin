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

    @State private var monthBase: Date = Date()
    @State private var selectedDay: Date? = nil
    @State private var selectedLogDetail: SelectedLogWrapper? = nil
    @State private var dayEditorTarget: DayEditorWrapper? = nil
    @State private var showingAddTypeDialog = false
    @State private var addMode: CalendarAddMode? = nil
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
                                    try? LogService.ensureLogs(for: key, modelContext: modelContext)
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
                                    .background(.thinMaterial)
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
                    .padding(.horizontal, isCompactLayout ? 8 : 12)

                    if let day = selectedDay {
                        compactListForSelectedDay(day)
                            .padding(.top, isCompactLayout ? 6 : 10)
                    }
                }
            }
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
                if selectedDayHasRows {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(L10n.tr("button_edit")) {
                            let target = selectedDay ?? Calendar.current.startOfDay(for: Date())
                            dayEditorTarget = DayEditorWrapper(date: target)
                        }
                        .foregroundStyle(AppTheme.brandRed)
                        .disabled(showingAddTypeDialog)
                        .opacity(showingAddTypeDialog ? 0.35 : 1)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAddTypeDialog = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .foregroundStyle(AppTheme.brandRed)
                    .disabled(showingAddTypeDialog)
                    .opacity(showingAddTypeDialog ? 0.35 : 1)
                }
            }
            .overlay {
                if showingAddTypeDialog {
                    CalendarAddMedicationTypeOverlay(
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
            .sheet(item: $addMode) { mode in
                let target = Calendar.current.startOfDay(for: selectedDay ?? Date())
                EditMedicationView(
                    medication: nil,
                    creationKind: mode.kind,
                    initialStartDate: target
                )
            }
            .onAppear {
                // Al menos crea logs para hoy (el resto se crea al entrar en cada día)
                try? LogService.ensureLogs(for: Date(), modelContext: modelContext)
                if selectedDay == nil {
                    selectedDay = Calendar.current.startOfDay(for: Date())
                }
            }
            .onChange(of: selectedDay) { _, newValue in
                if let d = newValue {
                    try? LogService.ensureLogs(for: d, modelContext: modelContext)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .calendarJumpToToday)) { _ in
                monthBase = Date()
                let today = Calendar.current.startOfDay(for: Date())
                selectedDay = today
                try? LogService.ensureLogs(for: today, modelContext: modelContext)
            }
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

        let activeMeds = medications.filter { $0.isActive }
        let due = activeMeds.filter { $0.isDue(on: key, calendar: cal) }
        if due.isEmpty { return .none } // blanco

        let dayLogs = logs.filter { cal.isDate($0.dateKey, inSameDayAs: key) }

        var takenCount = 0
        for med in due {
            let log = dayLogs.first(where: { $0.medicationID == med.id })
            if log?.isTaken == true {
                takenCount += 1
            }
            // si no hay log -> cuenta como no tomada (para no dar falsos verdes)
        }

        if takenCount == 0 { return .noneTaken }         // rojo
        if takenCount == due.count { return .allTaken }  // verde
        return .someTaken                                // amarillo
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
                    ForEach(items, id: \.med.id) { item in
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

        return due.compactMap { med in
            guard let log = dayLogs.first(where: { $0.medicationID == med.id }) else { return nil }
            return (med, log)
        }
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
}

private enum CalendarAddMode: Int, Identifiable {
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

private struct CalendarAddMedicationTypeOverlay: View {
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
