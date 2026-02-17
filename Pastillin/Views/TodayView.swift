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
    @AppStorage("selectedTab") private var selectedTab: AppTab = .today

    @State private var rows: [TodayRow] = []
    @State private var pendingCount: Int = 0
    @State private var selected: SelectedWrapper? = nil
    @State private var showingAddTypeDialog = false
    @State private var addMode: TodayAddMode? = nil
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
        isFirstRunOrCleanState && rows.isEmpty && !showingAddTypeDialog && !didDismissGettingStartedOverlay
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
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        showingAddTypeDialog = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .foregroundStyle(AppTheme.brandBlue)
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
                if showingAddTypeDialog {
                    TodayAddMedicationTypeOverlay(
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

                if shouldShowGettingStartedOverlay {
                    TodayGettingStartedOverlay(
                        plusFrame: plusButtonFrame,
                        helpFrame: helpButtonFrame,
                        onTapPlus: { showingAddTypeDialog = true },
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
                try? LogService.ensureLogs(for: Date(), modelContext: modelContext)
                normalizeSortOrderIfNeeded()
                reload()
            }
            .onChange(of: medications.count) { _, _ in
                try? LogService.ensureLogs(for: Date(), modelContext: modelContext)
                reload()
            }
            .onChange(of: logs.count) { _, _ in
                reload()
            }
            .sheet(item: $selected) { wrap in
                MedicationLogDetailView(
                    medication: wrap.med,
                    dayKey: wrap.dayKey,
                    log: wrap.log
                )
            }
            .sheet(item: $addMode) { mode in
                switch mode {
                case .scheduled:
                    EditMedicationView(
                        medication: nil,
                        creationKind: .scheduled,
                        markTakenNowOnCreate: false,
                        initialStartDate: Date()
                    )
                case .occasional:
                    EditMedicationView(
                        medication: nil,
                        creationKind: .occasional,
                        markTakenNowOnCreate: true,
                        initialStartDate: Date()
                    )
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

        let activeMeds = medications.filter { $0.isActive }
        let dueMeds = activeMeds.filter { $0.isDue(on: key, calendar: cal) }

        let todayLogs = logs.filter { cal.isDate($0.dateKey, inSameDayAs: key) }

        var temp: [TodayRow] = []
        for med in dueMeds {
            if let log = todayLogs.first(where: { $0.medicationID == med.id }) {
                temp.append(TodayRow(id: med.id, medication: med, log: log))
            }
        }
        rows = temp.sorted {
            let o0 = $0.medication.sortOrder ?? 0
            let o1 = $1.medication.sortOrder ?? 0
            if o0 != o1 {
                return o0 < o1
            }
            return $0.medication.name.localizedCaseInsensitiveCompare($1.medication.name) == .orderedAscending
        }

        refreshPendingCount()
    }

    private func refreshPendingCount() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let start = cal.date(byAdding: .day, value: -29, to: today) ?? today

        try? LogService.ensureLogs(from: start, to: today, modelContext: modelContext)

        let medsByID = Dictionary(uniqueKeysWithValues: medications.map { ($0.id, $0) })
        let missedRows: [(medication: Medication, log: IntakeLog)] = logs.compactMap { log in
            let dayKey = cal.startOfDay(for: log.dateKey)
            guard dayKey < today else { return nil }
            guard dayKey >= start else { return nil }
            guard !log.isTaken else { return nil }
            guard let med = medsByID[log.medicationID] else { return nil }
            guard med.kind == .scheduled else { return nil }
            guard isEligibleForPending(med) else { return nil }
            return (med, log)
        }

        var latestPendingByMedication: [UUID: IntakeLog] = [:]
        for row in missedRows {
            let medID = row.medication.id
            if let existing = latestPendingByMedication[medID] {
                if row.log.dateKey > existing.dateKey {
                    latestPendingByMedication[medID] = row.log
                }
            } else {
                latestPendingByMedication[medID] = row.log
            }
        }

        let validMedicationIDs = latestPendingByMedication.compactMap { medID, latestLog -> UUID? in
            let latestDay = cal.startOfDay(for: latestLog.dateKey)
            let hasLaterTaken = logs.contains { log in
                guard log.medicationID == medID else { return false }
                guard log.isTaken else { return false }
                let candidateDay = cal.startOfDay(for: log.dateKey)
                return candidateDay > latestDay && candidateDay <= today
            }
            return hasLaterTaken ? nil : medID
        }

        pendingCount = Set(validMedicationIDs).count
    }

    private func isEligibleForPending(_ medication: Medication) -> Bool {
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
        let startKey = cal.startOfDay(for: medication.startDate)
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

    enum TodayAddMode: Int, Identifiable {
        case scheduled
        case occasional

        var id: Int { rawValue }
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

private struct TodayAddMedicationTypeOverlay: View {
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
