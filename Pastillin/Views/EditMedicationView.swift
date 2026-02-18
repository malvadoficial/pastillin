import SwiftUI
import SwiftData
import PhotosUI
import UIKit
import WebKit

struct EditMedicationView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let medication: Medication?
    let creationKind: MedicationKind?
    let markTakenNowOnCreate: Bool
    let initialStartDate: Date?
    let prefill: MedicationPrefillData?

    @State private var name: String = ""
    @State private var note: String = ""
    @State private var isActive: Bool = true

    @State private var repeatUnit: RepeatUnit = .day
    @State private var interval: Int = 1
    @State private var isDailySchedule: Bool = true
    @State private var startDate: Date = Date()
    @State private var occasionalReminderEnabled: Bool = false
    @State private var occasionalReminderTime: Date = Date()
    @State private var occasionalPastTakenTime: Date = Date()
    @State private var hasEndDate: Bool = false
    @State private var endDate: Date = Date()

    @State private var photoData: Data? = nil
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var showCamera = false
    @State private var showLibrary = false
    @State private var showPickerSheet = false
    @State private var showPhotoPreview = false
    @State private var didCustomizePhotoManually = false
    @State private var showDeleteConfirmation = false
    @State private var cimaNRegistro: String? = nil
    @State private var cimaCN: String? = nil
    @State private var cimaNombreCompleto: String? = nil
    @State private var cimaPrincipioActivo: String? = nil
    @State private var cimaLaboratorio: String? = nil
    @State private var cimaProspectoURL: String? = nil
    @State private var isLoadingCIMADetail = false
    @State private var prospectoSheetURL: URLSheetItem? = nil
    @State private var historyLogForActions: IntakeLog? = nil
    @State private var historyEditedTime: Date = Date()
    @State private var isHistoryEditing: Bool = false
    @State private var showShoppingCart = false
    @State private var showAddToCartOnCreatePrompt = false

    @StateObject private var nameAutocomplete = MedicationNameAutocompleteViewModel()
    @FocusState private var focusedField: Field?
    private let cimaService = CIMAService()

    // 🔹 Logs para el historial
    @Query private var allLogs: [IntakeLog]
    @Query private var allMeds: [Medication]
    @Query private var appSettings: [AppSettings]
    private let maxHistoryItems = 30
    private var effectiveKind: MedicationKind { medication?.kind ?? creationKind ?? .scheduled }
    private var isOccasionalForm: Bool { effectiveKind == .occasional }
    private var isAutocompleteEnabled: Bool { appSettings.first?.medicationAutocompleteEnabled ?? true }
    private var canConfigureOccasionalReminder: Bool {
        let cal = Calendar.current
        return cal.startOfDay(for: startDate) > cal.startOfDay(for: Date())
    }
    private var isPastOccasionalDate: Bool {
        let cal = Calendar.current
        return cal.startOfDay(for: startDate) < cal.startOfDay(for: Date())
    }
    private var isTodayOccasionalDate: Bool {
        let cal = Calendar.current
        return cal.startOfDay(for: startDate) == cal.startOfDay(for: Date())
    }
    private var hasOfficialInfo: Bool {
        cimaNombreCompleto != nil || cimaPrincipioActivo != nil || cimaLaboratorio != nil || cimaProspectoURL != nil || cimaNRegistro != nil || cimaCN != nil
    }

    private enum Field {
        case name
        case note
    }

    init(
        medication: Medication?,
        creationKind: MedicationKind? = nil,
        markTakenNowOnCreate: Bool = false,
        initialStartDate: Date? = nil,
        prefill: MedicationPrefillData? = nil
    ) {
        self.medication = medication
        self.creationKind = creationKind
        self.markTakenNowOnCreate = markTakenNowOnCreate
        self.initialStartDate = initialStartDate
        self.prefill = prefill
    }

    var body: some View {
        NavigationStack {
            Form {

                // MARK: Medicamento
                Section(L10n.tr("section_medication")) {
                    TextField(L10n.tr("edit_field_name"), text: $name)
                        .focused($focusedField, equals: .name)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled(true)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .note }

                    if focusedField == .name && isAutocompleteEnabled {
                        if nameAutocomplete.isLoading {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text(L10n.tr("autocomplete_loading"))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        } else if !nameAutocomplete.suggestions.isEmpty {
                            ForEach(nameAutocomplete.suggestions) { suggestion in
                                Button {
                                    applySelectedSuggestion(suggestion)
                                    nameAutocomplete.clearResults(resetSearchState: true)
                                    focusedField = .note
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(suggestion.nombreConDosis)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        } else if nameAutocomplete.didSearch,
                                  name.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3 {
                            Text(L10n.tr("autocomplete_no_results"))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    TextField(L10n.tr("edit_field_note_optional"), text: $note)
                        .focused($focusedField, equals: .note)
                        .submitLabel(.done)
                        .onSubmit { focusedField = nil }

                    Toggle(L10n.tr("edit_toggle_active"), isOn: $isActive)
                }

                if hasOfficialInfo || isLoadingCIMADetail {
                    Section(L10n.tr("official_info_section_title")) {
                        if let nombreCompleto = cimaNombreCompleto {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L10n.tr("official_info_full_name"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(nombreCompleto)
                                    .font(.subheadline.weight(.semibold))
                            }
                        }

                        if let principioActivo = cimaPrincipioActivo {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L10n.tr("official_info_active_ingredient"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(principioActivo)
                                    .font(.subheadline.weight(.semibold))
                            }
                        }

                        if let laboratorio = cimaLaboratorio {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L10n.tr("official_info_laboratory"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(laboratorio)
                                    .font(.subheadline.weight(.semibold))
                            }
                        }

                        if let cn = cimaCN {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L10n.tr("official_info_cn"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(cn)
                                    .font(.subheadline.weight(.semibold))
                            }
                        }

                        if hasOfficialInfo {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L10n.tr("official_info_source"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(L10n.tr("official_info_source_value"))
                                    .font(.subheadline.weight(.semibold))
                            }
                        }

                        if isAutocompleteEnabled {
                            if let url = resolvedProspectoURL(from: cimaProspectoURL) {
                                Button {
                                    prospectoSheetURL = URLSheetItem(url: url)
                                } label: {
                                    Label(L10n.tr("official_info_leaflet_button"), systemImage: "doc.text")
                                }
                            }
                        }

                        if isLoadingCIMADetail {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text(L10n.tr("official_info_loading"))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                // MARK: Pauta
                if isOccasionalForm && isActive && medication == nil {
                    Section(L10n.tr("occasional_section_date")) {
                        DatePicker(
                            L10n.tr("occasional_date"),
                            selection: $startDate,
                            displayedComponents: [.date]
                        )

                        if isPastOccasionalDate {
                            DatePicker(
                                L10n.tr("occasional_taken_time"),
                                selection: $occasionalPastTakenTime,
                                displayedComponents: [.hourAndMinute]
                            )
                        }
                        if markTakenNowOnCreate && isTodayOccasionalDate {
                            DatePicker(
                                L10n.tr("occasional_taken_time"),
                                selection: $occasionalPastTakenTime,
                                displayedComponents: [.hourAndMinute]
                            )
                        }

                        if canConfigureOccasionalReminder {
                            Toggle(L10n.tr("occasional_reminder_toggle"), isOn: $occasionalReminderEnabled)
                            if occasionalReminderEnabled {
                                DatePicker(
                                    L10n.tr("occasional_reminder_time"),
                                    selection: $occasionalReminderTime,
                                    displayedComponents: [.hourAndMinute]
                                )
                            }
                        }
                    }
                } else if !isOccasionalForm && isActive {
                    Section(L10n.tr("edit_section_schedule")) {
                        DatePicker(L10n.tr("edit_date_start"), selection: $startDate, displayedComponents: [.date])

                        Toggle(L10n.tr("edit_toggle_chronic"), isOn: chronicBinding)
                        if !chronicBinding.wrappedValue {
                            DatePicker(L10n.tr("edit_date_end_included"), selection: $endDate, displayedComponents: [.date])
                        }

                        Toggle(L10n.tr("edit_toggle_daily"), isOn: $isDailySchedule)
                            .onChange(of: isDailySchedule) { _, newValue in
                                guard !isOccasionalForm else { return }
                                if newValue {
                                    repeatUnit = .day
                                    interval = 1
                                } else if repeatUnit == .day && interval == 1 {
                                    interval = 2
                                }
                            }

                        if !isDailySchedule {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(L10n.tr("edit_schedule_pattern_label"))
                                    .font(.subheadline.weight(.semibold))

                                HStack(alignment: .center, spacing: 10) {
                                    Text(L10n.tr("edit_schedule_every_prefix"))
                                        .font(.subheadline)

                                    Picker(L10n.tr("edit_schedule_number"), selection: $interval) {
                                        ForEach(1...99, id: \.self) { value in
                                            Text("\(value)").tag(value)
                                        }
                                    }
                                    .labelsHidden()
                                    .pickerStyle(.wheel)
                                    .frame(width: 72, height: 96)
                                    .clipped()

                                    Picker(L10n.tr("edit_picker_unit"), selection: $repeatUnit) {
                                        Text(L10n.tr("edit_unit_days")).tag(RepeatUnit.day)
                                        Text(L10n.tr("edit_unit_months")).tag(RepeatUnit.month)
                                    }
                                    .pickerStyle(.segmented)
                                }
                            }
                            .onChange(of: interval) { _, newValue in
                                guard !isOccasionalForm, !isDailySchedule else { return }
                                if repeatUnit == .day && newValue == 1 {
                                    isDailySchedule = true
                                }
                            }
                            .onChange(of: repeatUnit) { _, newValue in
                                guard !isOccasionalForm, !isDailySchedule else { return }
                                if newValue == .day && interval == 1 {
                                    isDailySchedule = true
                                }
                            }
                        }
                    }
                }

                Section(L10n.tr("section_photo")) {
                    if let data = photoData, let ui = UIImage(data: data) {
                        Image(uiImage: ui)
                            .resizable()
                            .scaledToFill()
                            .frame(height: 132)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .contentShape(Rectangle())
                            .onTapGesture { showPickerSheet = true }
                    } else {
                        MedicationDefaultArtworkView(
                            kind: currentDefaultArtworkKind,
                            width: nil,
                            height: 132,
                            cornerRadius: 12
                        )
                        .contentShape(Rectangle())
                        .onTapGesture { showPickerSheet = true }
                    }
                }

                if medication != nil {
                    Section {
                        Button {
                            medication?.inShoppingCart = true
                            if medication?.shoppingCartSortOrder == nil {
                                medication?.shoppingCartSortOrder = nextCartSortOrder
                            }
                            try? modelContext.save()
                        } label: {
                            Label(
                                medication?.inShoppingCart == true ? L10n.tr("cart_already_added") : L10n.tr("cart_add"),
                                systemImage: medication?.inShoppingCart == true ? "cart.fill" : "cart.badge.plus"
                            )
                            .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                }

                // MARK: Historial (solo si hay datos)
                if let med = medication {
                    let historyItems = history(for: med)
                    if !historyItems.isEmpty {
                    Section {
                        ForEach(Array(historyItems.enumerated()), id: \.element.id) { index, log in
                            historyRow(log, isLatest: index == 0)
                        }
                    } header: {
                        HStack {
                            if med.kind == .occasional {
                                Text(L10n.tr("occasional_section_intakes"))
                            } else {
                                Text(String(format: L10n.tr("edit_section_history_format"), maxHistoryItems))
                            }
                            Spacer()
                            Button(isHistoryEditing ? L10n.tr("button_done") : L10n.tr("button_edit")) {
                                isHistoryEditing.toggle()
                                if !isHistoryEditing {
                                    historyLogForActions = nil
                                }
                            }
                            .buttonStyle(.borderless)
                        }
                        .textCase(nil)
                    }
                }
                }

                if medication != nil {
                    Section {
                        Button(role: .destructive) {
                            showDeleteConfirmation = true
                        } label: {
                            Text(L10n.tr("edit_delete_medication"))
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                }

            }
            .navigationTitle(titleText)
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                if !showPickerSheet {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(L10n.tr("button_cancel")) { dismiss() }
                    }
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button {
                            showShoppingCart = true
                        } label: {
                            ShoppingCartIconView(count: shoppingCartCount)
                        }

                        Button(L10n.tr("button_save")) { onSaveTapped() }
                            .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button(L10n.tr("button_done")) {
                            focusedField = nil
                        }
                    }
                }
            }
            .onAppear { loadIfEditingOrPrefill() }
            .onChange(of: name) { _, newValue in
                guard isAutocompleteEnabled else {
                    nameAutocomplete.clearResults(resetSearchState: true)
                    return
                }
                if focusedField == .name {
                    nameAutocomplete.updateQuery(newValue)
                }
            }
            .onChange(of: startDate) { _, _ in
                guard isActive else { return }
                if !canConfigureOccasionalReminder {
                    occasionalReminderEnabled = false
                }
                if isPastOccasionalDate {
                    let cal = Calendar.current
                    let dayKey = cal.startOfDay(for: startDate)
                    if let med = medication,
                       let existing = allLogs.first(where: { $0.medicationID == med.id && cal.isDate($0.dateKey, inSameDayAs: dayKey) }),
                       let existingTime = existing.takenAt {
                        occasionalPastTakenTime = existingTime
                    } else {
                        occasionalPastTakenTime = Date()
                    }
                }
            }
            .overlay {
                if showPickerSheet {
                    PhotoSourceOverlay(
                        hasCamera: UIImagePickerController.isSourceTypeAvailable(.camera),
                        onChooseLibrary: openLibraryPicker,
                        onChooseCamera: openCameraPicker,
                        canViewPhoto: photoData != nil,
                        onViewPhoto: openPhotoPreview,
                        canDeletePhoto: photoData != nil,
                        onDeletePhoto: removePhoto,
                        onCancel: closePhotoPicker
                    )
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .zIndex(1)
                }
            }
            .overlay {
                if let log = historyLogForActions {
                    HistoryEditOverlay(
                        allowsDateEdition: isOccasionalForm,
                        selectedTime: $historyEditedTime,
                        onSaveTime: { saveHistoryTime(for: log) },
                        onDeleteIntake: { deleteHistoryLog(for: log) },
                        onClose: { historyLogForActions = nil }
                    )
                    .zIndex(2)
                    .transition(.opacity)
                }
            }
            .sheet(isPresented: $showCamera) {
                ImagePicker(sourceType: .camera, imageData: $photoData)
            }
            .sheet(isPresented: $showLibrary) {
                ImagePicker(sourceType: .photoLibrary, imageData: $photoData)
            }
            .sheet(isPresented: $showPhotoPreview) {
                if let data = photoData, let image = UIImage(data: data) {
                    NavigationStack {
                        LargePhotoPreview(image: image)
                            .toolbar {
                                ToolbarItem(placement: .topBarTrailing) {
                                    Button(L10n.tr("button_close")) {
                                        showPhotoPreview = false
                                    }
                                }
                            }
                    }
                }
            }
            .alert(L10n.tr("edit_delete_title"), isPresented: $showDeleteConfirmation) {
                Button(L10n.tr("button_cancel"), role: .cancel) {}
                Button(L10n.tr("edit_delete_confirm"), role: .destructive) {
                    deleteMedication()
                }
            } message: {
                Text(L10n.tr("edit_delete_message"))
            }
            .alert(L10n.tr("save_add_to_cart_prompt_title"), isPresented: $showAddToCartOnCreatePrompt) {
                Button(L10n.tr("save_add_to_cart_yes")) {
                    save(addToCartOnCreate: true)
                }
                Button(L10n.tr("save_add_to_cart_no")) {
                    save(addToCartOnCreate: false)
                }
                Button(L10n.tr("button_cancel"), role: .cancel) {}
            } message: {
                Text(L10n.tr("save_add_to_cart_prompt_message"))
            }
            .sheet(item: $prospectoSheetURL) { item in
                NavigationStack {
                    ProspectoScreen(url: item.url)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button(L10n.tr("button_close")) {
                                    prospectoSheetURL = nil
                                }
                            }
                    }
                }
            }
            .sheet(isPresented: $showShoppingCart) {
                NavigationStack {
                    ShoppingCartView()
                }
            }
            .animation(.easeInOut(duration: 0.2), value: showPickerSheet)
            .animation(.easeInOut(duration: 0.2), value: historyLogForActions?.id)
            .onDisappear {
                nameAutocomplete.cancel()
            }
        }
    }

    private var shoppingCartCount: Int {
        allMeds.filter { $0.inShoppingCart }.count
    }

    private var nextCartSortOrder: Int {
        (allMeds.compactMap { $0.shoppingCartSortOrder }.max() ?? -1) + 1
    }

    private var titleText: String {
        if medication != nil {
            return L10n.tr("edit_title_edit")
        }
        return isOccasionalForm ? L10n.tr("edit_title_new_occasional") : L10n.tr("edit_title_new")
    }

    // MARK: - Historial helpers

    private func history(for medication: Medication) -> [IntakeLog] {
        let filtered: [IntakeLog]
        if medication.kind == .occasional {
            let nameKey = normalizedMedicationName(medication.name)
            let siblingIDs = Set(
                allMeds
                    .filter { $0.kind == .occasional && normalizedMedicationName($0.name) == nameKey }
                    .map(\.id)
            )
            filtered = allLogs.filter { siblingIDs.contains($0.medicationID) }
        } else {
            filtered = allLogs.filter { $0.medicationID == medication.id }
        }

        let sorted = filtered.sorted {
            let lhsDate = $0.takenAt ?? $0.dateKey
            let rhsDate = $1.takenAt ?? $1.dateKey
            if lhsDate != rhsDate { return lhsDate > rhsDate }
            if $0.dateKey != $1.dateKey { return $0.dateKey > $1.dateKey }
            return $0.id.uuidString > $1.id.uuidString
        }

        return Array(sorted.prefix(maxHistoryItems))
    }

    @ViewBuilder
    private func historyRow(_ log: IntakeLog, isLatest: Bool = false) -> some View {
        HStack {
            if isHistoryEditing {
                Button {
                    beginHistoryActions(for: log)
                } label: {
                    historyRowMainContent(log)
                }
                .buttonStyle(.plain)
            } else {
                historyRowMainContent(log)
            }

            Spacer()

            if isHistoryEditing {
                Button {
                    toggleHistoryStatus(for: log)
                } label: {
                    Circle()
                        .frame(width: 12, height: 12)
                        .foregroundStyle(log.isTaken ? AppTheme.brandBlue : AppTheme.brandRed)
                }
                .buttonStyle(.plain)
            } else {
                Circle()
                    .frame(width: 10, height: 10)
                    .foregroundStyle(log.isTaken ? AppTheme.brandBlue : AppTheme.brandRed)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isLatest ? AppTheme.brandBlue.opacity(0.10) : Color.clear)
        )
    }

    @ViewBuilder
    private func historyRowMainContent(_ log: IntakeLog) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Fmt.dateShort(log.dateKey))
                .font(.subheadline.weight(.semibold))

            if log.isTaken {
                let timeText = log.takenAt.map { Fmt.timeShort($0) } ?? L10n.tr("time_unspecified")
                Text(String(format: L10n.tr("history_taken_time_format"), timeText))
                    .foregroundStyle(.secondary)
            } else {
                Text(L10n.tr("history_not_taken"))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Load / Save

    private func loadIfEditingOrPrefill() {
        if let med = medication {
            name = med.name
            note = med.note ?? ""
            isActive = med.isActive
            repeatUnit = med.repeatUnit
            interval = med.interval
            isDailySchedule = (repeatUnit == .day && interval == 1)
            if let configuredStartDate = med.startDateRaw {
                startDate = configuredStartDate
            }
            occasionalReminderEnabled = med.occasionalReminderEnabled
            let h = med.occasionalReminderHour ?? 9
            let m = med.occasionalReminderMinute ?? 0
            occasionalReminderTime = Calendar.current.date(
                from: DateComponents(
                    year: Calendar.current.component(.year, from: Date()),
                    month: Calendar.current.component(.month, from: Date()),
                    day: Calendar.current.component(.day, from: Date()),
                    hour: h,
                    minute: m
                )
            ) ?? Date()
            photoData = med.photoData
            cimaNRegistro = med.cimaNRegistro
            cimaCN = med.cimaCN
            cimaNombreCompleto = med.cimaNombreCompleto
            cimaPrincipioActivo = med.cimaPrincipioActivo
            cimaLaboratorio = med.cimaLaboratorio
            cimaProspectoURL = med.cimaProspectoURL

            if med.kind == .occasional {
                let cal = Calendar.current
                if let configuredStartDate = med.startDateRaw {
                    let dayKey = cal.startOfDay(for: configuredStartDate)
                    if let existing = allLogs.first(where: { $0.medicationID == med.id && cal.isDate($0.dateKey, inSameDayAs: dayKey) }),
                       let existingTime = existing.takenAt {
                        occasionalPastTakenTime = existingTime
                    } else {
                        occasionalPastTakenTime = Date()
                    }
                } else {
                    occasionalPastTakenTime = Date()
                }
            }

            if med.kind == .scheduled, let ed = med.endDate {
                hasEndDate = true
                endDate = ed
            } else {
                hasEndDate = false
            }
            return
        }

        if let initialStartDate {
            startDate = Calendar.current.startOfDay(for: initialStartDate)
        }
        if let prefill {
            name = prefill.name
            note = prefill.note ?? ""
            photoData = prefill.photoData
            cimaNRegistro = prefill.cimaNRegistro
            cimaCN = prefill.cimaCN
            cimaNombreCompleto = prefill.cimaNombreCompleto
            cimaPrincipioActivo = prefill.cimaPrincipioActivo
            cimaLaboratorio = prefill.cimaLaboratorio
            cimaProspectoURL = prefill.cimaProspectoURL
        }
        occasionalReminderEnabled = false
        occasionalReminderTime = Date()
        occasionalPastTakenTime = Date()
        isDailySchedule = true
    }

    private func onSaveTapped() {
        if medication == nil {
            showAddToCartOnCreatePrompt = true
            return
        }
        save(addToCartOnCreate: false)
    }

    private func save(addToCartOnCreate: Bool) {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let chosenDate = Calendar.current.startOfDay(for: startDate)
        let kind = effectiveKind

        let targetMed: Medication
        if let med = medication {
            med.name = cleanName
            med.note = note.isEmpty ? nil : note
            med.photoData = photoData
            med.kind = kind
            med.cimaNRegistro = cimaNRegistro
            med.cimaCN = normalizedOptional(cimaCN)
            med.cimaNombreCompleto = normalizedOptional(cimaNombreCompleto)
            med.cimaPrincipioActivo = normalizedOptional(cimaPrincipioActivo)
            med.cimaLaboratorio = normalizedOptional(cimaLaboratorio)
            med.cimaProspectoURL = normalizedOptional(cimaProspectoURL)

            if kind == .occasional {
                med.isActive = isActive
                med.repeatUnit = .day
                med.interval = 1
                if isActive {
                    med.startDate = chosenDate
                    med.endDate = nil
                    if canConfigureOccasionalReminder && occasionalReminderEnabled {
                        med.occasionalReminderEnabled = true
                        let hm = Calendar.current.dateComponents([.hour, .minute], from: occasionalReminderTime)
                        med.occasionalReminderHour = hm.hour ?? 9
                        med.occasionalReminderMinute = hm.minute ?? 0
                    } else {
                        med.occasionalReminderEnabled = false
                        med.occasionalReminderHour = nil
                        med.occasionalReminderMinute = nil
                    }
                } else {
                    med.startDateRaw = nil
                    med.endDate = nil
                    med.occasionalReminderEnabled = false
                    med.occasionalReminderHour = nil
                    med.occasionalReminderMinute = nil
                }
            } else {
                med.isActive = isActive
                if isActive {
                    med.repeatUnit = isDailySchedule ? .day : repeatUnit
                    med.interval = isDailySchedule ? 1 : max(1, interval)
                    med.startDate = chosenDate
                    med.endDate = hasEndDate ? endDate : nil
                } else {
                    med.startDateRaw = nil
                    med.endDate = nil
                }
                med.occasionalReminderEnabled = false
                med.occasionalReminderHour = nil
                med.occasionalReminderMinute = nil
            }
            targetMed = med
        } else {
            let nextOrder = ((allMeds.map { $0.sortOrder ?? 0 }.max()) ?? -1) + 1
            let med = Medication(
                name: cleanName,
                note: note.isEmpty ? nil : note,
                isActive: isActive,
                kind: kind,
                repeatUnit: kind == .occasional ? .day : (isDailySchedule ? .day : repeatUnit),
                interval: kind == .occasional ? 1 : (isDailySchedule ? 1 : max(1, interval)),
                startDate: chosenDate,
                endDate: kind == .occasional ? nil : (hasEndDate ? endDate : nil)
            )
            med.sortOrder = nextOrder
            med.photoData = photoData
            med.cimaNRegistro = cimaNRegistro
            med.cimaCN = normalizedOptional(cimaCN)
            med.cimaNombreCompleto = normalizedOptional(cimaNombreCompleto)
            med.cimaPrincipioActivo = normalizedOptional(cimaPrincipioActivo)
            med.cimaLaboratorio = normalizedOptional(cimaLaboratorio)
            med.cimaProspectoURL = normalizedOptional(cimaProspectoURL)
            if kind == .occasional && med.isActive && canConfigureOccasionalReminder && occasionalReminderEnabled {
                med.occasionalReminderEnabled = true
                let hm = Calendar.current.dateComponents([.hour, .minute], from: occasionalReminderTime)
                med.occasionalReminderHour = hm.hour ?? 9
                med.occasionalReminderMinute = hm.minute ?? 0
            } else {
                med.occasionalReminderEnabled = false
                med.occasionalReminderHour = nil
                med.occasionalReminderMinute = nil
            }
            modelContext.insert(med)
            if addToCartOnCreate {
                med.inShoppingCart = true
                med.shoppingCartSortOrder = nextCartSortOrder
            }
            if kind == .occasional && med.isActive {
                upsertOccasionalLogOnCreate(for: med, date: chosenDate)
            }
            if !med.isActive {
                med.startDateRaw = nil
                med.endDate = nil
                med.occasionalReminderEnabled = false
                med.occasionalReminderHour = nil
                med.occasionalReminderMinute = nil
            }
            targetMed = med
        }

        if kind == .occasional && targetMed.isActive {
            upsertOccasionalPastLogIfNeeded(for: targetMed, date: chosenDate)
        }

        try? modelContext.save()
        syncOccasionalReminder(for: targetMed)
        dismiss()
    }

    private func closePhotoPicker() {
        showPickerSheet = false
    }

    private func openLibraryPicker() {
        showPickerSheet = false
        didCustomizePhotoManually = true
        DispatchQueue.main.async {
            showLibrary = true
        }
    }

    private func openCameraPicker() {
        showPickerSheet = false
        didCustomizePhotoManually = true
        DispatchQueue.main.async {
            showCamera = true
        }
    }

    private func removePhoto() {
        didCustomizePhotoManually = true
        photoData = nil
        showPickerSheet = false
    }

    private func openPhotoPreview() {
        guard photoData != nil else { return }
        showPickerSheet = false
        showPhotoPreview = true
    }

    private func upsertOccasionalPastLogIfNeeded(for med: Medication, date: Date) {
        let cal = Calendar.current
        let dayKey = cal.startOfDay(for: date)
        guard dayKey < cal.startOfDay(for: Date()) else { return }

        let hm = cal.dateComponents([.hour, .minute], from: occasionalPastTakenTime)
        var comps = cal.dateComponents([.year, .month, .day], from: dayKey)
        comps.hour = hm.hour
        comps.minute = hm.minute
        let takenAt = cal.date(from: comps) ?? dayKey

        if let existing = allLogs.first(where: { $0.medicationID == med.id && cal.isDate($0.dateKey, inSameDayAs: dayKey) }) {
            existing.isTaken = true
            existing.takenAt = takenAt
        } else {
            modelContext.insert(IntakeLog(medicationID: med.id, dateKey: dayKey, isTaken: true, takenAt: takenAt))
        }
    }

    private func upsertOccasionalLogOnCreate(for med: Medication, date: Date) {
        guard markTakenNowOnCreate else { return }

        let cal = Calendar.current
        let dayKey = cal.startOfDay(for: date)
        let hm = cal.dateComponents([.hour, .minute], from: occasionalPastTakenTime)
        var comps = cal.dateComponents([.year, .month, .day], from: dayKey)
        comps.hour = hm.hour
        comps.minute = hm.minute
        let takenAt = cal.date(from: comps) ?? Date()

        if let existing = allLogs.first(where: { $0.medicationID == med.id && cal.isDate($0.dateKey, inSameDayAs: dayKey) }) {
            existing.isTaken = true
            existing.takenAt = takenAt
        } else {
            modelContext.insert(IntakeLog(medicationID: med.id, dateKey: dayKey, isTaken: true, takenAt: takenAt))
        }
    }

    private func deleteMedication() {
        guard let med = medication else { return }
        let medID = med.id

        for log in allLogs where log.medicationID == medID {
            modelContext.delete(log)
        }
        NotificationService.cancelOccasionalReminder(medicationID: medID)
        modelContext.delete(med)
        try? modelContext.save()
        dismiss()
    }

    private func beginHistoryActions(for log: IntakeLog) {
        let cal = Calendar.current
        let baseDay = cal.startOfDay(for: log.dateKey)
        if let takenAt = log.takenAt {
            historyEditedTime = takenAt
        } else {
            historyEditedTime = cal.date(
                bySettingHour: 9,
                minute: 0,
                second: 0,
                of: baseDay
            ) ?? baseDay
        }
        historyLogForActions = log
    }

    private func saveHistoryTime(for log: IntakeLog) {
        let cal = Calendar.current
        let editedDayKey = cal.startOfDay(for: historyEditedTime)
        let hm = cal.dateComponents([.hour, .minute], from: historyEditedTime)
        var comps = cal.dateComponents([.year, .month, .day], from: editedDayKey)
        comps.hour = hm.hour
        comps.minute = hm.minute
        let finalTakenAt = cal.date(from: comps) ?? editedDayKey

        log.isTaken = true
        if isOccasionalForm {
            log.dateKey = editedDayKey
            if let med = allMeds.first(where: { $0.id == log.medicationID }) {
                med.startDate = editedDayKey
            }
        }
        log.takenAt = finalTakenAt
        try? modelContext.save()
        historyLogForActions = nil
    }

    private func toggleHistoryStatus(for log: IntakeLog) {
        let cal = Calendar.current
        if log.isTaken {
            log.isTaken = false
            log.takenAt = nil
        } else {
            let nowHM = cal.dateComponents([.hour, .minute], from: Date())
            var comps = cal.dateComponents([.year, .month, .day], from: cal.startOfDay(for: log.dateKey))
            comps.hour = nowHM.hour
            comps.minute = nowHM.minute
            log.isTaken = true
            log.takenAt = cal.date(from: comps) ?? log.dateKey
        }
        try? modelContext.save()
    }

    private func deleteHistoryLog(for log: IntakeLog) {
        modelContext.delete(log)
        try? modelContext.save()
        historyLogForActions = nil
    }

    private func normalizedMedicationName(_ name: String) -> String {
        name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    }

    private func syncOccasionalReminder(for med: Medication) {
        guard med.kind == .occasional else {
            NotificationService.cancelOccasionalReminder(medicationID: med.id)
            return
        }
        guard med.occasionalReminderEnabled,
              let hour = med.occasionalReminderHour,
              let minute = med.occasionalReminderMinute else {
            NotificationService.cancelOccasionalReminder(medicationID: med.id)
            return
        }

        guard let configuredStartDate = med.startDateRaw else {
            NotificationService.cancelOccasionalReminder(medicationID: med.id)
            return
        }

        let cal = Calendar.current
        let dayKey = cal.startOfDay(for: configuredStartDate)
        guard dayKey > cal.startOfDay(for: Date()) else {
            NotificationService.cancelOccasionalReminder(medicationID: med.id)
            return
        }

        var comps = cal.dateComponents([.year, .month, .day], from: dayKey)
        comps.hour = hour
        comps.minute = minute
        let fireDate = cal.date(from: comps) ?? dayKey
        let medID = med.id
        let medName = med.name

        Task {
            do {
                let granted = try await NotificationService.requestAuthorization()
                guard granted else { return }
                try await NotificationService.scheduleOccasionalReminder(
                    medicationID: medID,
                    medicationName: medName,
                    at: fireDate
                )
            } catch {
                // No bloquea el guardado si falla la notificación
            }
        }
    }

    private func applySelectedSuggestion(_ suggestion: CIMAMedicationSuggestion) {
        name = suggestion.nombreConDosis
        didCustomizePhotoManually = false
        photoData = nil
        cimaNRegistro = suggestion.nregistro.isEmpty ? nil : suggestion.nregistro
        cimaCN = nil
        cimaNombreCompleto = normalizedOptional(suggestion.nombreCompleto)
        cimaPrincipioActivo = normalizedOptional(suggestion.principioActivo)
        cimaLaboratorio = normalizedOptional(suggestion.laboratorio)
        cimaProspectoURL = nil
        isLoadingCIMADetail = false

        guard let reg = cimaNRegistro else { return }
        isLoadingCIMADetail = true
        Task {
            let detail = try? await cimaService.fetchMedicationDetail(nregistro: reg)
            await MainActor.run {
                self.isLoadingCIMADetail = false
                guard self.cimaNRegistro == reg else { return }
                if let detail {
                    if let full = normalizedOptional(detail.nombreCompleto) {
                        self.cimaNombreCompleto = full
                    }
                    if let principio = normalizedOptional(detail.principioActivo) {
                        self.cimaPrincipioActivo = principio
                    }
                    if let lab = normalizedOptional(detail.laboratorio) {
                        self.cimaLaboratorio = lab
                    }
                    self.cimaCN = normalizedOptional(detail.cn)
                    self.cimaProspectoURL = normalizedOptional(detail.prospectoURL?.absoluteString)
                    if let imageURL = detail.imageURL {
                        Task {
                            let data = try? await cimaService.fetchImageData(url: imageURL)
                            await MainActor.run {
                                guard self.cimaNRegistro == reg else { return }
                                guard !self.didCustomizePhotoManually else { return }
                                guard let data, UIImage(data: data) != nil else { return }
                                self.photoData = data
                            }
                        }
                    }
                }
            }
        }
    }

    private func normalizedOptional(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var chronicBinding: Binding<Bool> {
        Binding(
            get: { !hasEndDate },
            set: { isChronic in
                hasEndDate = !isChronic
            }
        )
    }

    private var currentDefaultArtworkKind: MedicationDefaultArtworkKind {
        let currentRepeatUnit: RepeatUnit = isDailySchedule ? .day : repeatUnit
        let currentInterval: Int = isDailySchedule ? 1 : max(1, interval)
        let currentEndDate: Date? = hasEndDate ? endDate : nil
        return MedicationDefaultArtwork.kind(
            kind: effectiveKind,
            repeatUnit: currentRepeatUnit,
            interval: currentInterval,
            endDate: currentEndDate
        )
    }

    private func resolvedProspectoURL(from raw: String?) -> URL? {
        guard let raw = normalizedOptional(raw) else { return nil }
        if let direct = URL(string: raw), let scheme = direct.scheme, (scheme == "http" || scheme == "https") {
            return direct
        }
        if raw.hasPrefix("www."),
           let url = URL(string: "https://\(raw)") {
            return url
        }
        if raw.hasPrefix("cima.aemps.es"),
           let url = URL(string: "https://\(raw)") {
            return url
        }
        return nil
    }
}

struct MedicationPrefillData {
    let name: String
    let note: String?
    let photoData: Data?
    let cimaNRegistro: String?
    let cimaCN: String?
    let cimaNombreCompleto: String?
    let cimaPrincipioActivo: String?
    let cimaLaboratorio: String?
    let cimaProspectoURL: String?
}

private struct URLSheetItem: Identifiable {
    let id = UUID()
    let url: URL
}

private struct ProspectoScreen: View {
    let url: URL

    var body: some View {
        ProspectoWebView(url: url)
            .navigationTitle(L10n.tr("official_info_leaflet_button"))
            .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ProspectoWebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let web = WKWebView(frame: .zero)
        web.allowsBackForwardNavigationGestures = true
        web.backgroundColor = .systemBackground
        web.scrollView.backgroundColor = .systemBackground
        return web
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if webView.url != url {
            let request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 30)
            webView.load(request)
        }
    }
}

private struct PhotoSourceOverlay: View {
    let hasCamera: Bool
    let onChooseLibrary: () -> Void
    let onChooseCamera: () -> Void
    let canViewPhoto: Bool
    let onViewPhoto: () -> Void
    let canDeletePhoto: Bool
    let onDeletePhoto: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.62)
                .ignoresSafeArea()
                .onTapGesture {
                    onCancel()
                }

            VStack(spacing: 12) {
                Text(L10n.tr("photo_choose_title"))
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button(action: onChooseLibrary) {
                    Label(L10n.tr("photo_pick"), systemImage: "photo")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)

                if hasCamera {
                    Button(action: onChooseCamera) {
                        Label(L10n.tr("photo_take"), systemImage: "camera")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                }

                if canViewPhoto {
                    Button(action: onViewPhoto) {
                        Label(L10n.tr("photo_view"), systemImage: "photo")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                }

                if canDeletePhoto {
                    Button(role: .destructive, action: onDeletePhoto) {
                        Label(L10n.tr("photo_remove"), systemImage: "trash")
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
}

private struct LargePhotoPreview: View {
    let image: UIImage

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .padding(16)
        }
        .navigationTitle(L10n.tr("photo_view"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct HistoryEditOverlay: View {
    let allowsDateEdition: Bool
    @Binding var selectedTime: Date
    let onSaveTime: () -> Void
    let onDeleteIntake: () -> Void
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.62)
                .ignoresSafeArea()
                .onTapGesture {
                    onClose()
                }

            VStack(alignment: .leading, spacing: 14) {
                Text(L10n.tr("history_actions_title"))
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)

                DatePicker(
                    L10n.tr(allowsDateEdition ? "history_edit_datetime_picker" : "history_edit_time_picker"),
                    selection: $selectedTime,
                    displayedComponents: allowsDateEdition ? [.date, .hourAndMinute] : [.hourAndMinute]
                )
                .datePickerStyle(.wheel)
                .labelsHidden()
                .frame(maxWidth: .infinity)

                Button(action: onSaveTime) {
                    Label(
                        L10n.tr(allowsDateEdition ? "history_action_save_datetime" : "history_action_save_time"),
                        systemImage: "clock"
                    )
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.brandBlue)

                Button(role: .destructive, action: onDeleteIntake) {
                    Label(L10n.tr("history_action_delete"), systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button(L10n.tr("button_cancel"), action: onClose)
                    .frame(maxWidth: .infinity)
            }
            .padding(16)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(.horizontal, 16)
        }
    }
}

struct ImagePicker: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    let sourceType: UIImagePickerController.SourceType
    @Binding var imageData: Data?

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: ImagePicker
        init(_ parent: ImagePicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.imageData = image.jpegData(compressionQuality: 0.85)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
