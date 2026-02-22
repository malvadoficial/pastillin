import SwiftUI
import SwiftData
import PhotosUI
import UIKit
import WebKit

struct EditMedicationView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage("selectedTab") private var selectedTab: AppTab = .medications

    let medication: Medication?
    let creationKind: MedicationKind?
    let markTakenNowOnCreate: Bool
    let initialStartDate: Date?
    let overrideStartDateOnEdit: Date?
    let prefill: MedicationPrefillData?
    let openedFromCabinet: Bool

    @State private var name: String = ""
    @State private var note: String = ""
    @State private var isActive: Bool = true
    @State private var selectedCreationKind: MedicationKind

    @State private var repeatUnit: RepeatUnit = .day
    @State private var interval: Int = 1
    @State private var isDailySchedule: Bool = true
    @State private var threeTimesDaily: Bool = false
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
    @State private var showOfficialInfoExpanded = false
    @State private var prospectoSheetURL: URLSheetItem? = nil
    @State private var historyLogForActions: IntakeLog? = nil
    @State private var historyEditedTime: Date = Date()
    @State private var isHistoryEditing: Bool = false
    @State private var showAddToCartOnCreatePrompt = false
    @State private var showDuplicateScheduledMedicationAlert = false
    @State private var showOccasionalTodayIntakeAlert = false
    @State private var occasionalTodayIntakeTime: Date = Date()
    @State private var occasionalTodayIntakeWasUpdated = false
    @State private var showDeactivateReminderAlert = false

    @StateObject private var nameAutocomplete = MedicationNameAutocompleteViewModel()
    @FocusState private var focusedField: Field?
    private let cimaService = CIMAService()

    // 🔹 Logs para el historial
    @Query private var allLogs: [IntakeLog]
    @Query private var allIntakes: [Intake]
    @Query private var allMeds: [Medication]
    @Query private var appSettings: [AppSettings]
    private let maxHistoryItems = 30
    private var effectiveKind: MedicationKind {
        if let medication, medication.kind != .unspecified {
            return medication.kind
        }
        return selectedCreationKind
    }
    private var isOccasionalForm: Bool { effectiveKind == .occasional }
    private var canChooseKindOnCreate: Bool {
        if medication == nil { return isActive }
        return medication?.kind == .unspecified && isActive
    }
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
        overrideStartDateOnEdit: Date? = nil,
        prefill: MedicationPrefillData? = nil,
        openedFromCabinet: Bool = false
    ) {
        self.medication = medication
        self.creationKind = creationKind
        self.markTakenNowOnCreate = markTakenNowOnCreate
        self.initialStartDate = initialStartDate
        self.overrideStartDateOnEdit = overrideStartDateOnEdit
        self.prefill = prefill
        self.openedFromCabinet = openedFromCabinet
        self._selectedCreationKind = State(initialValue: creationKind ?? .scheduled)
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

                if canChooseKindOnCreate {
                    Section(L10n.tr("medication_add_type_title")) {
                        Picker(L10n.tr("medication_add_type_title"), selection: $selectedCreationKind) {
                            Text("Pautado").tag(MedicationKind.scheduled)
                            Text("Ocasional").tag(MedicationKind.occasional)
                        }
                        .pickerStyle(.segmented)
                    }
                }

                if let med = medication, med.kind == .occasional, openedFromCabinet {
                    Section {
                        Button {
                            addOccasionalIntakeToday(for: med)
                        } label: {
                            Label(L10n.tr("occasional_add_today_intake"), systemImage: "plus.circle.fill")
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                }

                if hasOfficialInfo || isLoadingCIMADetail {
                    Section {
                        DisclosureGroup(
                            isExpanded: $showOfficialInfoExpanded,
                            content: {
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
                            },
                            label: {
                                Text(L10n.tr("official_info_section_title"))
                            }
                        )
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
                        DatePicker(
                            L10n.tr("edit_date_start"),
                            selection: $startDate,
                            displayedComponents: [.date]
                        )

                        if !isDailySchedule && repeatUnit == .hour {
                            DatePicker(
                                L10n.tr("edit_time_start"),
                                selection: $startDate,
                                displayedComponents: [.hourAndMinute]
                            )
                        }

                        Toggle(L10n.tr("edit_toggle_chronic"), isOn: chronicBinding)
                        if !chronicBinding.wrappedValue {
                            DatePicker(L10n.tr("edit_date_end_included"), selection: $endDate, displayedComponents: [.date])
                        }

                        Toggle(L10n.tr("edit_schedule_three_times_daily"), isOn: $threeTimesDaily)
                            .onChange(of: threeTimesDaily) { _, newValue in
                                guard !isOccasionalForm else { return }
                                if newValue {
                                    isDailySchedule = true
                                    repeatUnit = .day
                                    interval = 1
                                }
                            }

                        if !threeTimesDaily {
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
                        }

                        if !threeTimesDaily && !isDailySchedule {
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
                                        Text(L10n.tr("edit_unit_hours")).tag(RepeatUnit.hour)
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
                                } else if newValue != .day {
                                    isDailySchedule = false
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
                        if shoppingCartCount > 0 {
                            Button {
                                selectedTab = .cart
                                dismiss()
                            } label: {
                                ShoppingCartIconView(count: shoppingCartCount)
                            }
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
            .onChange(of: isActive) { oldValue, newValue in
                if oldValue && !newValue {
                    showDeactivateReminderAlert = shouldShowDeactivateReminder()
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
                        onClearTime: { clearHistoryTime(for: log) },
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
            .alert(L10n.tr("duplicate_scheduled_medication_title"), isPresented: $showDuplicateScheduledMedicationAlert) {
                Button(L10n.tr("button_ok"), role: .cancel) {}
            } message: {
                Text(L10n.tr("duplicate_scheduled_medication_message"))
            }
            .alert(L10n.tr("occasional_add_today_intake_alert_title"), isPresented: $showOccasionalTodayIntakeAlert) {
                Button(L10n.tr("button_ok"), role: .cancel) {}
            } message: {
                let messageKey = occasionalTodayIntakeWasUpdated
                    ? "occasional_add_today_intake_alert_message_updated_format"
                    : "occasional_add_today_intake_alert_message_created_format"
                Text(
                    String(
                        format: L10n.tr(messageKey),
                        Fmt.dayMedium(occasionalTodayIntakeTime),
                        Fmt.timeShort(occasionalTodayIntakeTime)
                    )
                )
            }
            .alert("Medicamento inactivo", isPresented: $showDeactivateReminderAlert) {
                Button(L10n.tr("button_ok"), role: .cancel) {}
            } message: {
                Text(L10n.tr("medication_inactive_future_intakes_removed"))
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
        let cal = Calendar.current
        let todayKey = cal.startOfDay(for: Date())
        let filtered: [IntakeLog]
        if medication.kind == .occasional {
            let nameKey = normalizedMedicationName(medication.name)
            let siblingIDs = Set(
                allMeds
                    .filter { $0.kind == .occasional && normalizedMedicationName($0.name) == nameKey }
                    .map(\.id)
            )
            filtered = allLogs.filter {
                siblingIDs.contains($0.medicationID) && cal.startOfDay(for: $0.dateKey) <= todayKey
            }
        } else {
            filtered = allLogs.filter {
                $0.medicationID == medication.id && cal.startOfDay(for: $0.dateKey) <= todayKey
            }
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
            if med.kind == .occasional {
                selectedCreationKind = .occasional
            } else {
                selectedCreationKind = .scheduled
            }
            repeatUnit = med.repeatUnit
            interval = med.interval
            isDailySchedule = (repeatUnit == .day && interval == 1)
            threeTimesDaily = med.threeTimesDaily
            if let configuredStartDate = med.startDateRaw {
                startDate = configuredStartDate
            }
            if let overrideStartDateOnEdit {
                let cal = Calendar.current
                if med.repeatUnit == .hour {
                    let hm = cal.dateComponents([.hour, .minute], from: startDate)
                    var comps = cal.dateComponents([.year, .month, .day], from: cal.startOfDay(for: overrideStartDateOnEdit))
                    comps.hour = hm.hour
                    comps.minute = hm.minute
                    startDate = cal.date(from: comps) ?? cal.startOfDay(for: overrideStartDateOnEdit)
                } else {
                    startDate = cal.startOfDay(for: overrideStartDateOnEdit)
                }
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

            ensureScheduledHistoryCoverageIfNeeded(for: med)
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
        selectedCreationKind = creationKind ?? .scheduled
        occasionalReminderEnabled = false
        occasionalReminderTime = Date()
        occasionalPastTakenTime = Date()
        isDailySchedule = true
        threeTimesDaily = false
    }

    private func onSaveTapped() {
        if shouldBlockScheduledDuplicateOnCreate() {
            showDuplicateScheduledMedicationAlert = true
            return
        }

        if shouldPromptAddToCartOnCreate() {
            showAddToCartOnCreatePrompt = true
            return
        }
        save(addToCartOnCreate: false)
    }

    private func shouldPromptAddToCartOnCreate() -> Bool {
        guard medication == nil else { return false }

        let cleanNameKey = normalizedMedicationName(name)
        guard !cleanNameKey.isEmpty else { return false }

        let medsWithSameName = allMeds.filter {
            normalizedMedicationName($0.name) == cleanNameKey
        }

        // Preguntar si es un medicamento nuevo en el botiquín.
        if medsWithSameName.isEmpty {
            return true
        }

        // Preguntar también si no hay existencias (0) y aún no está en la lista de compra.
        return medsWithSameName.contains { med in
            med.shoppingCartRemainingDoses == 0 && !med.inShoppingCart
        }
    }

    private func save(addToCartOnCreate: Bool) {
        if shouldBlockScheduledDuplicateOnCreate() {
            showDuplicateScheduledMedicationAlert = true
            return
        }

        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var kind = effectiveKind
        if medication == nil && !isActive {
            kind = .unspecified
        }
        let usesThreeTimesDaily = kind == .scheduled && threeTimesDaily
        let selectedRepeatUnit: RepeatUnit = usesThreeTimesDaily ? .day : (isDailySchedule ? .day : repeatUnit)
        let selectedInterval = usesThreeTimesDaily ? 1 : (isDailySchedule ? 1 : max(1, interval))
        let chosenStartDate = normalizedStartDate(
            from: startDate,
            kind: kind,
            repeatUnit: selectedRepeatUnit
        )
        let chosenDay = Calendar.current.startOfDay(for: chosenStartDate)
        let previousScheduleSignature: ScheduledSignature? = medication.map { scheduledSignature(for: $0) }

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
                med.threeTimesDaily = false
                if isActive {
                    med.startDate = chosenDay
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
                    med.repeatUnit = selectedRepeatUnit
                    med.interval = selectedInterval
                    med.threeTimesDaily = usesThreeTimesDaily
                    med.startDate = chosenStartDate
                    med.endDate = hasEndDate ? endDate : nil
                } else {
                    med.startDateRaw = nil
                    med.endDate = nil
                    med.threeTimesDaily = false
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
                repeatUnit: kind == .occasional ? .day : selectedRepeatUnit,
                interval: kind == .occasional ? 1 : selectedInterval,
                startDate: kind == .occasional ? chosenDay : chosenStartDate,
                endDate: kind == .occasional ? nil : (hasEndDate ? endDate : nil)
            )
            med.threeTimesDaily = kind == .scheduled && usesThreeTimesDaily
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
                upsertOccasionalLogOnCreate(for: med, date: chosenDay)
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
            upsertOccasionalPastLogIfNeeded(for: targetMed, date: chosenDay)
        }

        let scheduleChanged = previousScheduleSignature.map { $0 != scheduledSignature(for: targetMed) } ?? true

        if kind == .scheduled, targetMed.isActive, targetMed.repeatUnit != .hour {
            if scheduleChanged {
                rebuildScheduledLogsForCurrentConfiguration(for: targetMed)
            } else {
                cleanupScheduledLogsForCurrentConfiguration(for: targetMed)
            }
        }

        if kind == .scheduled {
            if targetMed.isActive {
                syncScheduledIntakes(
                    for: targetMed,
                    scheduleChanged: scheduleChanged,
                    anchorDate: chosenStartDate
                )
                pruneScheduledIntakesAfterEndDatePreservingTaken(for: targetMed)
            } else {
                removeFutureScheduledIntakes(for: targetMed.id, referenceDate: Date())
                removeFutureLogs(for: targetMed.id, referenceDate: Date())
            }
        } else {
            removeAllIntakes(for: targetMed.id)
        }

        try? modelContext.save()
        NotificationCenter.default.post(name: .intakeLogsDidChange, object: nil)

        if kind == .scheduled,
           targetMed.isActive,
           targetMed.repeatUnit != .hour,
           let configuredStartDate = targetMed.startDateRaw {
            let cal = Calendar.current
            let start = cal.startOfDay(for: configuredStartDate)
            let today = cal.startOfDay(for: Date())
            if start <= today {
                try? LogService.ensureLogs(from: start, to: today, modelContext: modelContext)
            }
        }

        syncOccasionalReminder(for: targetMed)
        dismiss()
    }

    private func cleanupScheduledLogsForCurrentConfiguration(for medication: Medication) {
        guard medication.kind == .scheduled else { return }
        guard medication.isActive else { return }
        guard let configuredStartDate = medication.startDateRaw else { return }

        let cal = Calendar.current
        let startKey = cal.startOfDay(for: configuredStartDate)
        let todayKey = cal.startOfDay(for: Date())
        let endKey = medication.endDate.map { cal.startOfDay(for: $0) }
        let logs = (try? modelContext.fetch(FetchDescriptor<IntakeLog>())) ?? allLogs

        for log in logs where log.medicationID == medication.id {
            let dayKey = cal.startOfDay(for: log.dateKey)

            // Mantener historial tomado; limpiar solo restos automáticos no tomados.
            if log.isTaken { continue }

            if dayKey < startKey {
                modelContext.delete(log)
                continue
            }

            if let endKey, dayKey > endKey {
                modelContext.delete(log)
                continue
            }

            // En futuro, eliminar cualquier fecha que ya no encaje con la pauta actual.
            if dayKey >= todayKey, !medication.isDue(on: dayKey, calendar: cal) {
                modelContext.delete(log)
            }
        }
    }

    private func rebuildScheduledLogsForCurrentConfiguration(for medication: Medication) {
        guard medication.kind == .scheduled else { return }
        guard medication.isActive else { return }
        guard let configuredStartDate = medication.startDateRaw else { return }

        let cal = Calendar.current
        let startKey = cal.startOfDay(for: configuredStartDate)
        let todayKey = cal.startOfDay(for: Date())
        let logs = (try? modelContext.fetch(FetchDescriptor<IntakeLog>())) ?? allLogs

        // Al cambiar pauta/fechas, rehacemos solo hasta hoy para evitar duplicados en histórico.
        for log in logs where log.medicationID == medication.id {
            let dayKey = cal.startOfDay(for: log.dateKey)
            if dayKey <= todayKey && !log.isTaken {
                modelContext.delete(log)
            }
        }

        if startKey <= todayKey {
            try? LogService.ensureLogs(from: startKey, to: todayKey, modelContext: modelContext)
        }

        // Limpia solo residuos futuros que ya no encajen con la pauta nueva.
        cleanupScheduledLogsForCurrentConfiguration(for: medication)
    }

    private struct ScheduledSignature: Equatable {
        let kind: MedicationKind
        let isActive: Bool
        let threeTimesDaily: Bool
        let repeatUnit: RepeatUnit
        let interval: Int
        let startAnchor: Date?
        let endKey: Date?
    }

    private func scheduledSignature(for medication: Medication) -> ScheduledSignature {
        let cal = Calendar.current
        return ScheduledSignature(
            kind: medication.kind,
            isActive: medication.isActive,
            threeTimesDaily: medication.threeTimesDaily,
            repeatUnit: medication.repeatUnit,
            interval: medication.interval,
            startAnchor: medication.startDateRaw.map {
                medication.repeatUnit == .hour
                    ? normalizeHourlyMoment($0, calendar: cal)
                    : cal.startOfDay(for: $0)
            },
            endKey: medication.endDate.map { cal.startOfDay(for: $0) }
        )
    }

    private func shouldBlockScheduledDuplicateOnCreate() -> Bool {
        guard medication == nil else { return false }
        guard isActive else { return false }
        guard effectiveKind == .scheduled else { return false }

        let cleanNameKey = normalizedMedicationName(name)
        guard !cleanNameKey.isEmpty else { return false }

        return allMeds.contains {
            $0.kind == .scheduled && normalizedMedicationName($0.name) == cleanNameKey
        }
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

        removeAllIntakes(for: medID)
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

    private func clearHistoryTime(for log: IntakeLog) {
        let cal = Calendar.current
        let editedDayKey = cal.startOfDay(for: historyEditedTime)

        log.isTaken = true
        if isOccasionalForm {
            log.dateKey = editedDayKey
            if let med = allMeds.first(where: { $0.id == log.medicationID }) {
                med.startDate = editedDayKey
            }
        }
        log.takenAt = nil
        try? modelContext.save()
        historyLogForActions = nil
    }

    private func toggleHistoryStatus(for log: IntakeLog) {
        if log.isTaken {
            log.isTaken = false
            log.takenAt = nil
        } else {
            log.isTaken = true
            log.takenAt = nil
        }
        try? modelContext.save()
    }

    private func deleteHistoryLog(for log: IntakeLog) {
        modelContext.delete(log)
        try? modelContext.save()
        historyLogForActions = nil
    }

    private func addOccasionalIntakeToday(for med: Medication) {
        let cal = Calendar.current
        let now = Date()
        let todayKey = cal.startOfDay(for: now)
        let nameKey = normalizedMedicationName(med.name)
        let siblingOccasionalMeds = allMeds.filter {
            $0.kind == .occasional && normalizedMedicationName($0.name) == nameKey
        }

        let todayMed = siblingOccasionalMeds.first(where: { sibling in
            guard let start = sibling.startDateRaw else { return false }
            return cal.isDate(start, inSameDayAs: todayKey)
        })

        let targetMed: Medication
        if let todayMed {
            todayMed.isActive = true
            todayMed.startDate = todayKey
            targetMed = todayMed
            occasionalTodayIntakeWasUpdated = true
        } else {
            let newMed = Medication(
                name: med.name,
                note: med.note,
                isActive: true,
                kind: .occasional,
                repeatUnit: .day,
                interval: 1,
                startDate: todayKey,
                endDate: nil
            )
            newMed.sortOrder = med.sortOrder ?? ((allMeds.map { $0.sortOrder ?? 0 }.max()) ?? -1) + 1
            newMed.photoData = med.photoData
            newMed.cimaNRegistro = med.cimaNRegistro
            newMed.cimaCN = med.cimaCN
            newMed.cimaNombreCompleto = med.cimaNombreCompleto
            newMed.cimaPrincipioActivo = med.cimaPrincipioActivo
            newMed.cimaLaboratorio = med.cimaLaboratorio
            newMed.cimaProspectoURL = med.cimaProspectoURL
            newMed.occasionalReminderEnabled = false
            newMed.occasionalReminderHour = nil
            newMed.occasionalReminderMinute = nil
            modelContext.insert(newMed)
            targetMed = newMed
            occasionalTodayIntakeWasUpdated = false
        }

        if let existing = allLogs.first(where: { $0.medicationID == targetMed.id && cal.isDate($0.dateKey, inSameDayAs: todayKey) }) {
            existing.isTaken = true
            existing.takenAt = now
        } else {
            modelContext.insert(IntakeLog(medicationID: targetMed.id, dateKey: todayKey, isTaken: true, takenAt: now))
        }

        try? modelContext.save()

        occasionalTodayIntakeTime = now
        showOccasionalTodayIntakeAlert = true
    }

    private func normalizedMedicationName(_ name: String) -> String {
        name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    }

    private func shouldShowDeactivateReminder() -> Bool {
        guard let med = medication else { return false }
        guard med.kind == .scheduled else { return false }
        let cal = Calendar.current
        let todayKey = cal.startOfDay(for: Date())
        return allIntakes.contains { intake in
            intake.medicationID == med.id &&
            intake.source == .scheduled &&
            cal.startOfDay(for: intake.scheduledAt) > todayKey
        }
    }

    private func ensureScheduledHistoryCoverageIfNeeded(for medication: Medication) {
        guard medication.kind == .scheduled else { return }
        guard medication.isActive else { return }
        guard let configuredStartDate = medication.startDateRaw else { return }

        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())

        let lookbackDays: Int
        switch medication.repeatUnit {
        case .day:
            lookbackDays = maxHistoryItems * max(1, medication.interval) + 7
        case .month:
            lookbackDays = maxHistoryItems * max(1, medication.interval) * 31 + 31
        case .hour:
            // En pautas por horas no hay una sola "toma por día"; evitamos reconstrucción legacy.
            return
        }

        let earliestNeeded = cal.date(byAdding: .day, value: -lookbackDays, to: today) ?? today
        let start = max(cal.startOfDay(for: configuredStartDate), cal.startOfDay(for: earliestNeeded))
        guard start <= today else { return }

        try? LogService.ensureLogs(from: start, to: today, modelContext: modelContext)
    }

    private func syncScheduledIntakes(for medication: Medication, scheduleChanged: Bool, anchorDate: Date) {
        guard medication.kind == .scheduled else { return }
        guard medication.isActive else { return }

        let anchor = medication.repeatUnit == .hour
            ? normalizeHourlyMoment(anchorDate)
            : Calendar.current.startOfDay(for: anchorDate)
        if scheduleChanged {
            try? IntakeSchedulingService.regenerateFutureIntakes(
                for: medication,
                from: anchor,
                modelContext: modelContext
            )
        } else {
            try? IntakeSchedulingService.generateInitialIntakes(
                for: medication,
                modelContext: modelContext,
                referenceDate: anchor
            )
        }
    }

    private func removeAllIntakes(for medicationID: UUID) {
        let descriptor = FetchDescriptor<Intake>(
            predicate: #Predicate { $0.medicationID == medicationID }
        )
        let intakes = (try? modelContext.fetch(descriptor)) ?? []
        for intake in intakes {
            modelContext.delete(intake)
        }
    }

    private func removeFutureScheduledIntakes(for medicationID: UUID, referenceDate: Date) {
        let cal = Calendar.current
        let todayKey = cal.startOfDay(for: referenceDate)
        let descriptor = FetchDescriptor<Intake>(
            predicate: #Predicate { $0.medicationID == medicationID }
        )
        let intakes = (try? modelContext.fetch(descriptor)) ?? []
        for intake in intakes where intake.source == .scheduled {
            if cal.startOfDay(for: intake.scheduledAt) > todayKey {
                modelContext.delete(intake)
            }
        }
    }

    private func removeFutureLogs(for medicationID: UUID, referenceDate: Date) {
        let cal = Calendar.current
        let todayKey = cal.startOfDay(for: referenceDate)
        for log in allLogs where log.medicationID == medicationID {
            if cal.startOfDay(for: log.dateKey) > todayKey {
                modelContext.delete(log)
            }
        }
    }

    private func pruneScheduledIntakesAfterEndDatePreservingTaken(for medication: Medication) {
        guard medication.kind == .scheduled else { return }
        guard let endDate = medication.endDate else { return }

        let cal = Calendar.current
        let endKey = cal.startOfDay(for: endDate)
        let medicationID = medication.id

        let intakeDescriptor = FetchDescriptor<Intake>(
            predicate: #Predicate { $0.medicationID == medicationID }
        )
        let medicationIntakes = (try? modelContext.fetch(intakeDescriptor)) ?? []

        let logDescriptor = FetchDescriptor<IntakeLog>(
            predicate: #Predicate { $0.medicationID == medicationID }
        )
        let medicationLogs = (try? modelContext.fetch(logDescriptor)) ?? []

        // Toma "tomada" = existe log tomado asociado al intakeID.
        let takenIntakeIDs = Set(
            medicationLogs.compactMap { log -> UUID? in
                guard log.isTaken, let intakeID = log.intakeID else { return nil }
                return intakeID
            }
        )

        // Fallback para datos legacy: logs tomados sin intakeID (1 toma/día).
        let preserveTakenLegacyDays: Set<Date> = {
            guard medication.repeatUnit != .hour, !medication.threeTimesDaily else { return [] }
            return Set(
                medicationLogs.compactMap { log -> Date? in
                    guard log.isTaken, log.intakeID == nil else { return nil }
                    return cal.startOfDay(for: log.dateKey)
                }
            )
        }()

        for intake in medicationIntakes where intake.source == .scheduled {
            let intakeDay = cal.startOfDay(for: intake.scheduledAt)
            guard intakeDay > endKey else { continue }
            if takenIntakeIDs.contains(intake.id) { continue }
            if preserveTakenLegacyDays.contains(intakeDay) { continue }
            modelContext.delete(intake)
        }

        // Limpia logs no tomados posteriores al fin; conserva tomados para histórico.
        for log in medicationLogs {
            let logDay = cal.startOfDay(for: log.dateKey)
            guard logDay > endKey else { continue }
            if log.isTaken { continue }
            modelContext.delete(log)
        }
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

    private func normalizedStartDate(from date: Date, kind: MedicationKind, repeatUnit: RepeatUnit) -> Date {
        let cal = Calendar.current
        if kind == .occasional {
            return cal.startOfDay(for: date)
        }
        if repeatUnit == .hour {
            return normalizeHourlyMoment(date, calendar: cal)
        }
        return cal.startOfDay(for: date)
    }

    private func normalizeHourlyMoment(_ date: Date, calendar: Calendar = .current) -> Date {
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return calendar.date(from: components) ?? date
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
    let onClearTime: () -> Void
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

                Button(action: onClearTime) {
                    Label(L10n.tr("button_clear"), systemImage: "xmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.brandYellow)

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
