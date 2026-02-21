//
//  MedicationLogDetailView.swift
//  MediRecord
//
//  Created by José Manuel Rives on 11/2/26.
//

import SwiftUI
import SwiftData
import UIKit

struct MedicationLogDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var medications: [Medication]
    @Query private var allLogs: [IntakeLog]
    @Query private var allIntakes: [Intake]
    @Query private var appSettings: [AppSettings]
    @AppStorage("selectedTab") private var selectedTab: AppTab = .today
    @AppStorage("shoppingCartDisclaimerShown") private var shoppingCartDisclaimerShown: Bool = false

    let medication: Medication
    let dayKey: Date              // startOfDay del día seleccionado
    @Bindable var log: IntakeLog  // el log de ese día para esa medicina
    @State private var showRemoveForDayConfirmation = false
    @State private var showDeleteOccasionalConfirmation = false
    @State private var showShoppingDisclaimerAlert = false
    @State private var showDateEditor = false
    @State private var editedDate: Date = Date()
    @State private var pendingAddToCart = false
    @State private var pendingOpenCart = false
    @State private var showOfficialInfoExpanded = false
    private var officialFullName: String? { normalized(medication.cimaNombreCompleto) }
    private var officialActiveIngredient: String? { normalized(medication.cimaPrincipioActivo) }
    private var officialLaboratory: String? { normalized(medication.cimaLaboratorio) }
    private var officialCN: String? { normalized(medication.cimaCN) }
    private var officialProspectoURL: URL? {
        resolvedProspectoURL(from: medication.cimaProspectoURL)
    }
    private var hasOfficialInfo: Bool {
        officialFullName != nil || officialActiveIngredient != nil || officialLaboratory != nil || officialCN != nil || officialProspectoURL != nil || normalized(medication.cimaNRegistro) != nil
    }
    private var isAEMPSIntegrationEnabled: Bool {
        appSettings.first?.medicationAutocompleteEnabled ?? true
    }
    private var isFutureDay: Bool {
        let cal = Calendar.current
        return cal.startOfDay(for: dayKey) > cal.startOfDay(for: Date())
    }
    private var canToggleTaken: Bool {
        // En fechas futuras no se puede pasar a "Tomado".
        !isFutureDay || log.isTaken
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(L10n.tr("section_medication")) {
                    HStack(spacing: 12) {
                        medicationThumbnail
                        Text(medication.name).font(.headline)
                    }
                    if let note = medication.note, !note.isEmpty {
                        Text(note).foregroundStyle(.secondary)
                    }
                    Button {
                        editedDate = dayKey
                        showDateEditor = true
                    } label: {
                        HStack(spacing: 6) {
                            Text(String(format: L10n.tr("detail_day_label_format"), dateString(dayKey)))
                                .foregroundStyle(.secondary)
                            Image(systemName: "calendar")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }

                if hasOfficialInfo {
                    Section {
                        DisclosureGroup(
                            isExpanded: $showOfficialInfoExpanded,
                            content: {
                                if let fullName = officialFullName {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(L10n.tr("official_info_full_name"))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Text(fullName)
                                            .font(.subheadline.weight(.semibold))
                                    }
                                }

                                if let activeIngredient = officialActiveIngredient {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(L10n.tr("official_info_active_ingredient"))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Text(activeIngredient)
                                            .font(.subheadline.weight(.semibold))
                                    }
                                }

                                if let laboratory = officialLaboratory {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(L10n.tr("official_info_laboratory"))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Text(laboratory)
                                            .font(.subheadline.weight(.semibold))
                                    }
                                }

                                if let cn = officialCN {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(L10n.tr("official_info_cn"))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Text(cn)
                                            .font(.subheadline.weight(.semibold))
                                    }
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(L10n.tr("official_info_source"))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(L10n.tr("official_info_source_value"))
                                        .font(.subheadline.weight(.semibold))
                                }

                                if isAEMPSIntegrationEnabled, let url = officialProspectoURL {
                                    Link(destination: url) {
                                        Label(L10n.tr("official_info_leaflet_button"), systemImage: "doc.text")
                                    }
                                }
                            },
                            label: {
                                Text(L10n.tr("official_info_section_title"))
                            }
                        )
                    }
                }

                if canToggleTaken {
                    Section(L10n.tr("detail_section_status_toggle")) {
                        Button {
                            toggleTaken()
                        } label: {
                            HStack {
                                Spacer()
                                Text(log.isTaken ? L10n.tr("detail_status_taken_current") : L10n.tr("detail_status_not_taken_current"))
                                    .font(.headline)
                                    .padding(.vertical, 12)
                                Spacer()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(log.isTaken ? AppTheme.brandBlue : AppTheme.brandRed)
                    }
                }

                if log.isTaken {
                    Section(L10n.tr("detail_section_time")) {
                        // La hora solo se puede editar si está tomado
                        DatePicker(
                            L10n.tr("detail_label_time_taken"),
                            selection: takenAtBinding,
                            displayedComponents: [.hourAndMinute]
                        )

                        Button {
                            clearTakenTime()
                        } label: {
                            Label(L10n.tr("button_clear"), systemImage: "xmark.circle")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Section {
                    Button {
                        requestAddToCart()
                    } label: {
                        Label(
                            medication.inShoppingCart ? L10n.tr("cart_already_added") : L10n.tr("cart_add"),
                            systemImage: medication.inShoppingCart ? "cart.fill" : "cart.badge.plus"
                        )
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                }

                if medication.kind == .scheduled {
                    Section {
                        Button(role: .destructive) {
                            showRemoveForDayConfirmation = true
                        } label: {
                            Text(L10n.tr("detail_remove_for_day"))
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                }

                if medication.kind == .occasional {
                    Section {
                        Button(role: .destructive) {
                            showDeleteOccasionalConfirmation = true
                        } label: {
                            Text(L10n.tr("detail_delete_intake"))
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                }
            }
            .textSelection(.enabled)
            .navigationTitle(L10n.tr("detail_title"))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.tr("button_close")) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        requestCartOpen()
                    } label: {
                        ShoppingCartIconView(count: shoppingCartCount)
                    }
                }
            }
            .alert(L10n.tr("detail_remove_for_day_title"), isPresented: $showRemoveForDayConfirmation) {
                Button(L10n.tr("button_cancel"), role: .cancel) {}
                Button(L10n.tr("detail_remove_for_day_confirm"), role: .destructive) {
                    removeScheduledForThisDay()
                }
            } message: {
                Text(L10n.tr("detail_remove_for_day_message"))
            }
            .alert(L10n.tr("detail_delete_intake_title"), isPresented: $showDeleteOccasionalConfirmation) {
                Button(L10n.tr("button_cancel"), role: .cancel) {}
                Button(L10n.tr("edit_delete_confirm"), role: .destructive) {
                    deleteOccasionalMedication()
                }
            } message: {
                Text(L10n.tr("detail_delete_intake_message"))
            }
            .alert(L10n.tr("cart_disclaimer_title"), isPresented: $showShoppingDisclaimerAlert) {
                Button(L10n.tr("cart_disclaimer_understood")) {
                    shoppingCartDisclaimerShown = true
                    runPendingCartAction()
                }
            } message: {
                Text(L10n.tr("cart_disclaimer_message"))
            }
            .sheet(isPresented: $showDateEditor) {
                NavigationStack {
                    Form {
                        Section {
                            DatePicker(
                                L10n.tr("occasional_date"),
                                selection: $editedDate,
                                displayedComponents: [.date]
                            )
                            .datePickerStyle(.graphical)
                        }
                    }
                    .navigationTitle(L10n.tr("occasional_date"))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button(L10n.tr("button_cancel")) {
                                showDateEditor = false
                            }
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(L10n.tr("button_save")) {
                                updateScheduledDate(to: editedDate)
                                showDateEditor = false
                            }
                        }
                    }
                }
            }
        }
    }

    private var shoppingCartCount: Int {
        medications.filter { $0.inShoppingCart }.count
    }

    private func requestCartOpen() {
        if shoppingCartDisclaimerShown {
            selectedTab = .cart
            dismiss()
            return
        }
        pendingOpenCart = true
        pendingAddToCart = false
        showShoppingDisclaimerAlert = true
    }

    private func requestAddToCart() {
        if shoppingCartDisclaimerShown {
            medication.inShoppingCart = true
            if medication.shoppingCartSortOrder == nil {
                medication.shoppingCartSortOrder = nextCartSortOrder
            }
            try? modelContext.save()
            return
        }
        pendingAddToCart = true
        pendingOpenCart = false
        showShoppingDisclaimerAlert = true
    }

    private func runPendingCartAction() {
        if pendingOpenCart {
            selectedTab = .cart
            dismiss()
        } else if pendingAddToCart {
            medication.inShoppingCart = true
            if medication.shoppingCartSortOrder == nil {
                medication.shoppingCartSortOrder = nextCartSortOrder
            }
            try? modelContext.save()
        }
        clearPendingCartAction()
    }

    private func clearPendingCartAction() {
        pendingOpenCart = false
        pendingAddToCart = false
    }

    private var nextCartSortOrder: Int {
        (medications.compactMap { $0.shoppingCartSortOrder }.max() ?? -1) + 1
    }

    // MARK: - Bindings

    private var takenBinding: Binding<Bool> {
        Binding(
            get: { log.isTaken },
            set: { newValue in
                if newValue {
                    // Si pasa a "Tomado" y no tenía hora:
                    // - hoy: hora actual
                    // - otro día: sin hora (se mostrará como no especificada)
                    if log.takenAt == nil {
                        let cal = Calendar.current
                        let isToday = cal.isDateInToday(dayKey)
                        log.takenAt = isToday ? Date() : nil
                    }
                    log.isTaken = true
                } else {
                    log.isTaken = false
                    log.takenAt = nil
                }
                try? modelContext.save()
                NotificationCenter.default.post(name: .intakeLogsDidChange, object: nil)
            }
        )
    }

    private var takenAtBinding: Binding<Date> {
        Binding(
            get: { log.takenAt ?? dayKey },
            set: { newTime in
                // Guardamos la hora elegida pero en el MISMO día (dayKey)
                let cal = Calendar.current
                let hm = cal.dateComponents([.hour, .minute], from: newTime)
                var comps = cal.dateComponents([.year, .month, .day], from: dayKey)
                comps.hour = hm.hour
                comps.minute = hm.minute
                let final = cal.date(from: comps) ?? dayKey

                log.takenAt = final
                try? modelContext.save()
                NotificationCenter.default.post(name: .intakeLogsDidChange, object: nil)
            }
        )
    }

    private func clearTakenTime() {
        guard log.isTaken else { return }
        log.takenAt = nil
        try? modelContext.save()
        NotificationCenter.default.post(name: .intakeLogsDidChange, object: nil)
    }

    // MARK: - Helpers

    private func dateString(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = .current
        f.dateStyle = .full
        f.timeStyle = .none
        return f.string(from: d)
    }

    private func normalized(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func resolvedProspectoURL(from raw: String?) -> URL? {
        guard let raw = normalized(raw) else { return nil }
        if let direct = URL(string: raw), direct.scheme != nil {
            return direct
        }
        if raw.hasPrefix("www."),
           let https = URL(string: "https://\(raw)") {
            return https
        }
        if raw.hasPrefix("cima.aemps.es"),
           let https = URL(string: "https://\(raw)") {
            return https
        }
        return nil
    }

    private func toggleTaken() {
        if !canToggleTaken { return }

        let cal = Calendar.current
        let isToday = cal.isDateInToday(dayKey)

        if log.isTaken {
            // Pasar a "No tomado"
            log.isTaken = false
            log.takenAt = nil
        } else {
            // Pasar a "Tomado"
            log.isTaken = true
            if log.takenAt == nil {
                log.takenAt = isToday ? Date() : nil
            }
        }

        try? modelContext.save()
        NotificationCenter.default.post(name: .intakeLogsDidChange, object: nil)
    }

    @ViewBuilder
    private var medicationThumbnail: some View {
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

    private func removeScheduledForThisDay() {
        guard medication.kind == .scheduled else { return }
        medication.setSkipped(true, on: dayKey)
        if let intakeID = log.intakeID,
           let intake = allIntakes.first(where: { $0.id == intakeID }) {
            modelContext.delete(intake)
        }
        modelContext.delete(log)
        try? modelContext.save()
        NotificationCenter.default.post(name: .intakeLogsDidChange, object: nil)
        dismiss()
    }

    private func updateScheduledDate(to newDate: Date) {
        let cal = Calendar.current
        if medication.repeatUnit == .hour {
            let oldDate: Date
            let oldTimeComponents: DateComponents
            if let intakeID = log.intakeID,
               let intake = allIntakes.first(where: { $0.id == intakeID }) {
                oldDate = normalizedHourlyMoment(intake.scheduledAt, calendar: cal)
                oldTimeComponents = cal.dateComponents([.hour, .minute], from: intake.scheduledAt)
            } else {
                oldDate = normalizedHourlyMoment(log.dateKey, calendar: cal)
                oldTimeComponents = DateComponents(hour: 12, minute: 0)
            }
            let newDay = cal.startOfDay(for: newDate)
            var comps = cal.dateComponents([.year, .month, .day], from: newDay)
            comps.hour = oldTimeComponents.hour ?? 12
            comps.minute = oldTimeComponents.minute ?? 0
            let normalizedNewDate = normalizedHourlyMoment(cal.date(from: comps) ?? newDay, calendar: cal)
            guard oldDate != normalizedNewDate else { return }

            if medication.kind == .scheduled,
               let intakeID = log.intakeID,
               let intake = allIntakes.first(where: { $0.id == intakeID }) {
                try? IntakeSchedulingService.moveScheduledIntakeAndReflow(
                    medication: medication,
                    intake: intake,
                    newDate: normalizedNewDate,
                    modelContext: modelContext
                )
            } else if let intakeID = log.intakeID,
                      let intake = allIntakes.first(where: { $0.id == intakeID }) {
                intake.scheduledAt = normalizedNewDate
            }

            let newDayKey = cal.startOfDay(for: normalizedNewDate)
            log.dateKey = newDayKey
            if let takenAt = log.takenAt {
                let hm = cal.dateComponents([.hour, .minute], from: takenAt)
                var comps = cal.dateComponents([.year, .month, .day], from: newDayKey)
                comps.hour = hm.hour
                comps.minute = hm.minute
                log.takenAt = cal.date(from: comps) ?? newDayKey
            }

            try? modelContext.save()
            NotificationCenter.default.post(name: .intakeLogsDidChange, object: nil)
            return
        }

        let oldDay = cal.startOfDay(for: log.dateKey)
        let newDay = cal.startOfDay(for: newDate)
        guard oldDay != newDay else { return }

        if medication.kind == .scheduled,
           let intakeID = log.intakeID,
           let intake = allIntakes.first(where: { $0.id == intakeID }) {
            try? IntakeSchedulingService.moveScheduledIntakeAndReflow(
                medication: medication,
                intake: intake,
                newDate: newDay,
                modelContext: modelContext
            )
        } else if let intakeID = log.intakeID,
                  let intake = allIntakes.first(where: { $0.id == intakeID }) {
            intake.scheduledAt = cal.date(bySettingHour: 12, minute: 0, second: 0, of: newDay) ?? newDay
        }

        log.dateKey = newDay
        if let takenAt = log.takenAt {
            let hm = cal.dateComponents([.hour, .minute], from: takenAt)
            var comps = cal.dateComponents([.year, .month, .day], from: newDay)
            comps.hour = hm.hour
            comps.minute = hm.minute
            log.takenAt = cal.date(from: comps) ?? newDay
        }

        try? modelContext.save()
        NotificationCenter.default.post(name: .intakeLogsDidChange, object: nil)
    }

    private func normalizedHourlyMoment(_ date: Date, calendar: Calendar) -> Date {
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return calendar.date(from: components) ?? date
    }

    private func deleteOccasionalMedication() {
        guard medication.kind == .occasional else { return }
        for entry in allLogs where entry.medicationID == medication.id {
            modelContext.delete(entry)
        }
        NotificationService.cancelOccasionalReminder(medicationID: medication.id)
        modelContext.delete(medication)
        try? modelContext.save()
        NotificationCenter.default.post(name: .intakeLogsDidChange, object: nil)
        dismiss()
    }

}
