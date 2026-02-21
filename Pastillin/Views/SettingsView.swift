import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settings: [AppSettings]
    @AppStorage("legalDisclaimerAccepted") private var legalDisclaimerAccepted = false
    @AppStorage("deleteAllDataNow") private var deleteAllDataNow = false
    @AppStorage("deleteAllDataCompleted") private var deleteAllDataCompleted = false

    @State private var reminderTimes: [Date] = []
    @State private var enabled: Bool = false
    @State private var autocompleteEnabled: Bool = true
    @State private var appearanceMode: UIAppearanceMode = .system

    @State private var reportFrom: Date = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    @State private var reportTo: Date = Date()
    @State private var reportURL: URL? = nil

    @State private var backupShareItem: ShareURLItem? = nil
    @State private var showingBackupImporter = false
    @State private var pendingRestoreURL: URL? = nil
    @State private var showRestoreConfirmation = false
    @State private var showDeleteAllConfirmation = false
    @State private var showDeleteAllSuccessAlert = false
    @State private var showLegalDisclaimerAfterDelete = false
    @State private var showAEMPSInfoAlert = false
    @State private var showAboutSheet = false
    @State private var showTutorial = false

    @State private var errorText: String? = nil

    var body: some View {
        NavigationStack {
            Form {
                Section(L10n.tr("settings_section_reminder")) {
                    Toggle(L10n.tr("settings_toggle_enable"), isOn: $enabled)
                        .onChange(of: enabled) { _, newValue in
                            Task { await applyNotificationSetting(newValue) }
                        }

                    ForEach(Array(reminderTimes.indices), id: \.self) { index in
                        HStack {
                            DatePicker(
                                String(format: L10n.tr("settings_label_time_format"), index + 1),
                                selection: reminderBinding(index),
                                displayedComponents: [.hourAndMinute]
                            )
                            .disabled(!enabled)

                            if reminderTimes.count > 1 {
                                Button(role: .destructive) {
                                    removeReminder(at: index)
                                } label: {
                                    Image(systemName: "minus.circle")
                                }
                                .disabled(!enabled)
                            }
                        }
                    }

                    if reminderTimes.count < 3 {
                        Button {
                            addReminder()
                        } label: {
                            Label(L10n.tr("settings_add_reminder"), systemImage: "plus.circle")
                        }
                        .disabled(!enabled)
                    }
                }

                Section(L10n.tr("settings_section_appearance")) {
                    Picker(L10n.tr("settings_appearance_mode"), selection: $appearanceMode) {
                        Text(L10n.tr("settings_appearance_system")).tag(UIAppearanceMode.system)
                        Text(L10n.tr("settings_appearance_light")).tag(UIAppearanceMode.light)
                        Text(L10n.tr("settings_appearance_dark")).tag(UIAppearanceMode.dark)
                    }
                    .onChange(of: appearanceMode) { _, newValue in
                        persistSettings(
                            reminderMinutesOfDay: reminderMinutesOfDay(),
                            enabled: enabled,
                            autocompleteEnabled: autocompleteEnabled,
                            appearanceMode: newValue
                        )
                    }
                }

                Section {
                    Toggle(L10n.tr("settings_toggle_autocomplete"), isOn: $autocompleteEnabled)
                        .onChange(of: autocompleteEnabled) { _, newValue in
                            persistSettings(
                                reminderMinutesOfDay: reminderMinutesOfDay(),
                                enabled: enabled,
                                autocompleteEnabled: newValue,
                                appearanceMode: appearanceMode
                            )
                        }

                    if autocompleteEnabled {
                        NavigationLink {
                            AEMPSSearchView()
                        } label: {
                            Label(L10n.tr("settings_open_aemps_search"), systemImage: "magnifyingglass")
                        }
                    }
                } header: {
                    HStack(spacing: 8) {
                        Text(L10n.tr("settings_section_autocomplete"))
                        Button {
                            showAEMPSInfoAlert = true
                        } label: {
                            Image(systemName: "questionmark.circle")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(AppTheme.brandBlue)
                    }
                }

                Section(L10n.tr("settings_section_report")) {
                    DatePicker(L10n.tr("settings_label_from"), selection: $reportFrom, displayedComponents: [.date])
                    DatePicker(L10n.tr("settings_label_to"), selection: $reportTo, displayedComponents: [.date])

                    Button(L10n.tr("settings_button_generate_pdf")) { generateReport() }

                    if let url = reportURL {
                        ShareLink(item: url) {
                            Text(L10n.tr("settings_button_share_report"))
                        }
                    }
                }

                Section(L10n.tr("settings_section_backup")) {
                    Button(L10n.tr("settings_button_generate_backup")) {
                        generateBackup()
                    }

                    Button(L10n.tr("settings_button_restore_backup")) {
                        showingBackupImporter = true
                    }
                }

                Section(L10n.tr("settings_section_help")) {
                    Button {
                        showTutorial = true
                    } label: {
                        Label(L10n.tr("settings_open_tutorial"), systemImage: "play.rectangle")
                    }

                    NavigationLink {
                        HelpView()
                    } label: {
                        Label(L10n.tr("settings_open_help"), systemImage: "questionmark.circle")
                    }
                }

                if let e = errorText {
                    Section {
                        Text(e).foregroundStyle(AppTheme.brandRed)
                    }
                }

                Section {
                    Button(role: .destructive) {
                        showDeleteAllConfirmation = true
                    } label: {
                        Text(L10n.tr("settings_button_delete_all_data"))
                    }
                } header: {
                    Label {
                        Text(L10n.tr("settings_section_danger"))
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(AppTheme.brandRed)
                    }
                }

                Section(L10n.tr("settings_section_legal")) {
                    NavigationLink {
                        LegalDisclaimerView(isMandatory: false, onAccept: nil)
                    } label: {
                        Label(L10n.tr("settings_open_legal"), systemImage: "doc.text")
                    }
                }

                Section(L10n.tr("settings_section_about")) {
                    Button {
                        showAboutSheet = true
                    } label: {
                        Label(L10n.tr("settings_open_about"), systemImage: "info.circle")
                    }
                }

                Section {
                    HStack {
                        Spacer()
                        Text(appVersionText)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }
            }
            .safeAreaPadding(.bottom, 84)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    NavigationTitleWithIcon(
                        title: L10n.tr("settings_title"),
                        systemImage: "gearshape",
                        color: .black
                    )
                }
            }
            .onAppear { loadOrCreateSettings() }
            .onChange(of: deleteAllDataCompleted) { _, newValue in
                guard newValue else { return }
                deleteAllDataCompleted = false
                legalDisclaimerAccepted = false
                loadOrCreateSettings()
                reportURL = nil
                backupShareItem = nil
                errorText = nil
                showDeleteAllSuccessAlert = true
            }
            .fileImporter(
                isPresented: $showingBackupImporter,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    pendingRestoreURL = url
                    showRestoreConfirmation = true
                case .failure:
                    errorText = L10n.tr("error_restore_backup")
                }
            }
            .alert(L10n.tr("settings_restore_confirm_title"), isPresented: $showRestoreConfirmation) {
                Button(L10n.tr("button_cancel"), role: .cancel) {
                    pendingRestoreURL = nil
                }
                Button(L10n.tr("settings_restore_confirm_button"), role: .destructive) {
                    restoreBackupIfConfirmed()
                }
            } message: {
                Text(L10n.tr("settings_restore_confirm_message"))
            }
            .alert(L10n.tr("settings_delete_all_confirm_title"), isPresented: $showDeleteAllConfirmation) {
                Button(L10n.tr("button_cancel"), role: .cancel) {}
                Button(L10n.tr("settings_delete_all_confirm_button"), role: .destructive) {
                    deleteAllDataIfConfirmed()
                }
            } message: {
                Text(L10n.tr("settings_delete_all_confirm_message"))
            }
            .alert(L10n.tr("settings_delete_all_success_title"), isPresented: $showDeleteAllSuccessAlert) {
                Button(L10n.tr("button_ok"), role: .cancel) {
                    showLegalDisclaimerAfterDelete = true
                }
            } message: {
                Text(L10n.tr("settings_delete_all_success_message"))
            }
            .alert(L10n.tr("settings_aemps_info_title"), isPresented: $showAEMPSInfoAlert) {
                Button(L10n.tr("button_ok"), role: .cancel) {}
            } message: {
                Text(L10n.tr("settings_aemps_info_message"))
            }
            .fullScreenCover(isPresented: $showLegalDisclaimerAfterDelete) {
                LegalDisclaimerView(isMandatory: true) {
                    legalDisclaimerAccepted = true
                    showLegalDisclaimerAfterDelete = false
                }
            }
            .sheet(item: $backupShareItem) { item in
                ActivityShareSheet(activityItems: [item.url])
            }
            .sheet(isPresented: $showAboutSheet) {
                NavigationStack {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            Text(aboutAttributedText)
                                .padding(.top, 8)
                                .font(.body)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(16)
                    }
                    .navigationTitle(L10n.tr("settings_section_about"))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(L10n.tr("button_close")) {
                                showAboutSheet = false
                            }
                        }
                    }
                }
            }
            .fullScreenCover(isPresented: $showTutorial) {
                TutorialView()
            }
        }
    }

    private var aboutAttributedText: AttributedString {
        // Preserva saltos exactamente como se escriben en Localizable, manteniendo markdown inline.
        let raw = L10n.tr("settings_about_text")
        let withRealBreaks = raw.replacingOccurrences(of: "\\n", with: "\n")
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .inlineOnlyPreservingWhitespace
        if let attributed = try? AttributedString(markdown: withRealBreaks, options: options) {
            return attributed
        }
        return AttributedString(withRealBreaks)
    }

    private var appVersionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        switch (version, build) {
        case let (v?, b?) where !v.isEmpty && !b.isEmpty:
            return "Versión \(v) (\(b))"
        case let (v?, _):
            return "Versión \(v)"
        case let (_, b?):
            return "Build \(b)"
        default:
            return "Versión"
        }
    }

    private func loadOrCreateSettings() {
        let s: AppSettings
        if let existing = settings.first(where: { $0.id == "app" }) {
            s = existing
        } else {
            s = AppSettings()
            modelContext.insert(s)
            try? modelContext.save()
        }

        enabled = s.notificationsEnabled
        autocompleteEnabled = s.medicationAutocompleteEnabled
        appearanceMode = s.uiAppearanceMode

        reminderTimes = s.reminderTimesInMinutes.map { dateFrom(minutesOfDay: $0) }
        if reminderTimes.isEmpty {
            reminderTimes = [dateFrom(minutesOfDay: 10 * 60)]
        }
    }

    private func persistSettings(reminderMinutesOfDay: [Int], enabled: Bool, autocompleteEnabled: Bool, appearanceMode: UIAppearanceMode) {
        let s = settings.first(where: { $0.id == "app" }) ?? AppSettings()
        if s.id != "app" { s.id = "app" }
        s.reminderTimesInMinutes = reminderMinutesOfDay
        s.notificationsEnabled = enabled
        s.medicationAutocompleteEnabled = autocompleteEnabled
        s.uiAppearanceMode = appearanceMode
        if !settings.contains(where: { $0.id == "app" }) {
            modelContext.insert(s)
        }
        try? modelContext.save()
    }

    private func reminderMinutesOfDay() -> [Int] {
        let raw = reminderTimes.map { minutesOfDay(from: $0) }
        let unique = Array(Set(raw)).sorted()
        return Array(unique.prefix(3))
    }

    private func minutesOfDay(from date: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        let h = min(max(c.hour ?? 10, 0), 23)
        let m = min(max(c.minute ?? 0, 0), 59)
        return h * 60 + m
    }

    private func dateFrom(minutesOfDay: Int) -> Date {
        let safe = min(max(minutesOfDay, 0), 23 * 60 + 59)
        var comps = DateComponents()
        comps.hour = safe / 60
        comps.minute = safe % 60
        return Calendar.current.date(from: comps) ?? Date()
    }

    private func reminderBinding(_ index: Int) -> Binding<Date> {
        Binding(
            get: {
                guard reminderTimes.indices.contains(index) else { return Date() }
                return reminderTimes[index]
            },
            set: { newValue in
                guard reminderTimes.indices.contains(index) else { return }
                reminderTimes[index] = newValue
                Task { await rescheduleIfNeeded() }
            }
        )
    }

    private func addReminder() {
        guard reminderTimes.count < 3 else { return }
        let base = reminderTimes.last ?? Date()
        let next = Calendar.current.date(byAdding: .hour, value: 4, to: base) ?? Date()
        reminderTimes.append(next)
        Task { await rescheduleIfNeeded() }
    }

    private func removeReminder(at index: Int) {
        guard reminderTimes.indices.contains(index) else { return }
        guard reminderTimes.count > 1 else { return }
        reminderTimes.remove(at: index)
        Task { await rescheduleIfNeeded() }
    }

    private func applyNotificationSetting(_ turnOn: Bool) async {
        let minutes = reminderMinutesOfDay()
        if turnOn {
            do {
                let ok = try await NotificationService.requestAuthorization()
                if !ok {
                    enabled = false
                    persistSettings(reminderMinutesOfDay: minutes, enabled: false, autocompleteEnabled: autocompleteEnabled, appearanceMode: appearanceMode)
                    return
                }
                let times = minutes.map { ($0 / 60, $0 % 60) }
                try await NotificationService.scheduleDailyReminders(times: times)
                persistSettings(reminderMinutesOfDay: minutes, enabled: true, autocompleteEnabled: autocompleteEnabled, appearanceMode: appearanceMode)
            } catch {
                errorText = L10n.tr("error_enable_reminder")
                enabled = false
                persistSettings(reminderMinutesOfDay: minutes, enabled: false, autocompleteEnabled: autocompleteEnabled, appearanceMode: appearanceMode)
            }
        } else {
            NotificationService.cancelDailyReminder()
            persistSettings(reminderMinutesOfDay: minutes, enabled: false, autocompleteEnabled: autocompleteEnabled, appearanceMode: appearanceMode)
        }
    }

    private func rescheduleIfNeeded() async {
        let minutes = reminderMinutesOfDay()
        persistSettings(reminderMinutesOfDay: minutes, enabled: enabled, autocompleteEnabled: autocompleteEnabled, appearanceMode: appearanceMode)

        guard enabled else { return }
        do {
            let times = minutes.map { ($0 / 60, $0 % 60) }
            try await NotificationService.scheduleDailyReminders(times: times)
        } catch {
            errorText = L10n.tr("error_reschedule_reminder")
        }
    }

    private func generateReport() {
        do {
            reportURL = try ReportService.generatePDF(from: reportFrom, to: reportTo, modelContext: modelContext)
            errorText = nil
        } catch {
            reportURL = nil
            errorText = L10n.tr("error_generate_report")
        }
    }

    private func generateBackup() {
        do {
            let url = try BackupService.generateBackup(modelContext: modelContext)
            errorText = nil
            backupShareItem = ShareURLItem(url: url)
        } catch {
            backupShareItem = nil
            errorText = L10n.tr("error_generate_backup")
        }
    }

    private func restoreBackupIfConfirmed() {
        guard let url = pendingRestoreURL else { return }
        pendingRestoreURL = nil

        let granted = url.startAccessingSecurityScopedResource()
        defer {
            if granted { url.stopAccessingSecurityScopedResource() }
        }

        do {
            try BackupService.restoreBackup(from: url, modelContext: modelContext)
            loadOrCreateSettings()
            errorText = nil
        } catch {
            errorText = L10n.tr("error_restore_backup")
        }
    }

    private func deleteAllDataIfConfirmed() {
        errorText = nil
        deleteAllDataNow = true
    }
}

private struct ShareURLItem: Identifiable {
    let id = UUID()
    let url: URL
}

private struct ActivityShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
