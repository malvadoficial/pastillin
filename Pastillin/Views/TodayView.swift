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

    @State private var rows: [TodayRow] = []
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
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text(row.medication.name)
                                        .font(.headline)

                                    if row.medication.kind == .occasional {
                                        Text(L10n.tr("medication_occasional_badge_short"))
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(AppTheme.brandBlue)
                                    }
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
            let safeTop = proxy.safeAreaInsets.top
            let plusTarget = normalizedPlusFrame(in: proxy.size, safeTop: safeTop)
            let helpTarget = normalizedHelpFrame(in: proxy.size)

            ZStack {
                Color.black.opacity(0.70)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .frame(width: plusTarget.width + 12, height: plusTarget.height + 10)
                            .position(x: plusTarget.midX, y: plusTarget.midY)
                            .blendMode(.destinationOut)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .frame(width: helpTarget.width + 34, height: helpTarget.height + 18)
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
                        .frame(width: max(helpTarget.width + 8, 140), height: max(helpTarget.height + 8, 40))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .position(x: helpTarget.midX, y: helpTarget.midY)

                Text(L10n.tr("today_overlay_plus_hint"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .frame(width: min(220, proxy.size.width - 24))
                    .position(
                        x: max(110, min(proxy.size.width - 110, plusTarget.midX + 70)),
                        y: min(proxy.size.height - 40, plusTarget.maxY + 46)
                    )

                Text(L10n.tr("today_overlay_help_hint"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .frame(width: min(300, proxy.size.width - 24))
                    .position(
                        x: helpTarget.midX,
                        y: max(26, helpTarget.minY - 34)
                    )
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
