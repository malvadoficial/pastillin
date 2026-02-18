import SwiftUI
import UIKit
import WebKit

private struct AEMPSDetailWrapper: Identifiable {
    let id = UUID()
    let suggestion: CIMAMedicationSuggestion
}

private struct AEMPSURLSheetItem: Identifiable {
    let id = UUID()
    let url: URL
}

private enum AEMPSAddMode: Int, Identifiable {
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

struct AEMPSSearchView: View {
    @State private var searchText: String = ""
    @State private var searchField: CIMASearchField = .name
    @State private var authorizedOnly: Bool = true
    @State private var commercializedOnly: Bool = true
    @State private var prescriptionFilter: CIMAPrescriptionFilter = .indifferent
    @State private var results: [CIMAMedicationSuggestion] = []
    @State private var isSearching = false
    @State private var didSearch = false
    @State private var selectedMedication: AEMPSDetailWrapper? = nil

    private let cimaService = CIMAService()

    var body: some View {
        List {
            Section(L10n.tr("aemps_search_section")) {
                HStack(spacing: 8) {
                    TextField(L10n.tr("aemps_search_query_placeholder"), text: $searchText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .submitLabel(.done)

                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                            results = []
                            didSearch = false
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L10n.tr("button_clear"))
                    }
                }

                Picker(L10n.tr("aemps_search_mode"), selection: $searchField) {
                    Text(L10n.tr("aemps_search_mode_name")).tag(CIMASearchField.name)
                    Text(L10n.tr("aemps_search_mode_active")).tag(CIMASearchField.activeIngredient)
                    Text(L10n.tr("aemps_search_mode_registration")).tag(CIMASearchField.registration)
                }

                Toggle(L10n.tr("aemps_filter_authorized"), isOn: $authorizedOnly)
                Toggle(L10n.tr("aemps_filter_commercialized"), isOn: $commercializedOnly)

                Picker(L10n.tr("aemps_filter_prescription"), selection: $prescriptionFilter) {
                    Text(L10n.tr("aemps_filter_prescription_indifferent")).tag(CIMAPrescriptionFilter.indifferent)
                    Text(L10n.tr("aemps_filter_prescription_yes")).tag(CIMAPrescriptionFilter.withPrescription)
                    Text(L10n.tr("aemps_filter_prescription_no")).tag(CIMAPrescriptionFilter.withoutPrescription)
                }

                Button {
                    runSearch()
                } label: {
                    HStack {
                        Spacer()
                        if isSearching { ProgressView().padding(.trailing, 4) }
                        Text(L10n.tr("aemps_search_button"))
                        Spacer()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSearching || !canSearch)
            }

            Section(L10n.tr("aemps_search_results")) {
                if isSearching && results.isEmpty {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text(L10n.tr("autocomplete_loading"))
                            .foregroundStyle(.secondary)
                    }
                } else if results.isEmpty {
                    Text(didSearch ? L10n.tr("autocomplete_no_results") : L10n.tr("aemps_search_results_hint"))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(results) { result in
                        Button {
                            selectedMedication = AEMPSDetailWrapper(suggestion: result)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(result.nombreConDosis)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)

                                if let active = result.principioActivo {
                                    Text(active)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }

                                if !result.nregistro.isEmpty {
                                    Text(String(format: L10n.tr("aemps_registration_format"), result.nregistro))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .navigationTitle(L10n.tr("aemps_search_title"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedMedication) { wrapper in
            NavigationStack {
                AEMPSMedicationDetailView(suggestion: wrapper.suggestion)
            }
        }
    }

    private var canSearch: Bool {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        switch searchField {
        case .registration: return !trimmed.isEmpty
        case .name, .activeIngredient: return trimmed.count >= 3
        }
    }

    private func runSearch() {
        guard canSearch else { return }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filters = CIMASearchFilters(
            authorizedOnly: authorizedOnly,
            commercializedOnly: commercializedOnly,
            prescriptionFilter: prescriptionFilter
        )

        isSearching = true
        Task {
            let found = (try? await cimaService.searchMedications(
                query: query,
                field: searchField,
                filters: filters,
                page: 1,
                limit: 50
            )) ?? []

            await MainActor.run {
                results = found
                didSearch = true
                isSearching = false
            }
        }
    }
}

private struct AEMPSMedicationDetailView: View {
    @Environment(\.dismiss) private var dismiss

    let suggestion: CIMAMedicationSuggestion

    @State private var detail: CIMAMedicationDetail? = nil
    @State private var imageData: Data? = nil
    @State private var isLoadingDetail = false
    @State private var addMode: AEMPSAddMode? = nil
    @State private var showingAddTypeDialog = false
    @State private var documentSheetURL: AEMPSURLSheetItem? = nil
    @State private var showAdditionalInfo = false

    private let cimaService = CIMAService()

    var body: some View {
        Form {
            Section(L10n.tr("section_medication")) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(suggestion.nombreConDosis)
                        .font(.headline)

                    if !suggestion.nregistro.isEmpty {
                        Text(String(format: L10n.tr("aemps_registration_format"), suggestion.nregistro))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let imageData,
                       let ui = UIImage(data: imageData) {
                        Image(uiImage: ui)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, minHeight: 150, maxHeight: 240)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
            }

            Section(L10n.tr("official_info_section_title")) {
                if let fullName = normalized(detail?.nombreCompleto ?? suggestion.nombreCompleto) {
                    infoRow(title: L10n.tr("official_info_full_name"), value: fullName)
                }
                if let active = normalized(detail?.principioActivo ?? suggestion.principioActivo) {
                    infoRow(title: L10n.tr("official_info_active_ingredient"), value: active)
                }
                if let lab = normalized(detail?.laboratorio ?? suggestion.laboratorio) {
                    infoRow(title: L10n.tr("official_info_laboratory"), value: lab)
                }
                if let cn = normalized(detail?.cn) {
                    infoRow(title: L10n.tr("official_info_cn"), value: cn)
                }
                if let prescriptionText = normalized(detail?.prescriptionLabel ?? suggestion.prescriptionLabel) {
                    infoRow(title: L10n.tr("aemps_prescription_label"), value: prescriptionText)
                }
                if let requiresPrescription = detail?.requiresPrescription ?? suggestion.requiresPrescription {
                    infoRow(title: L10n.tr("aemps_requires_prescription"), value: boolText(requiresPrescription))
                }
                if let isAuthorized = detail?.isAuthorized ?? suggestion.isAuthorized {
                    infoRow(title: L10n.tr("aemps_is_authorized"), value: boolText(isAuthorized))
                }
                if let isCommercialized = detail?.isCommercialized ?? suggestion.isCommercialized {
                    infoRow(title: L10n.tr("aemps_is_commercialized"), value: boolText(isCommercialized))
                }

                infoRow(title: L10n.tr("official_info_source"), value: L10n.tr("official_info_source_value"))

                if isLoadingDetail {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text(L10n.tr("official_info_loading"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if additionalInfoAvailable {
                Section {
                    DisclosureGroup(L10n.tr("aemps_additional_info_section"), isExpanded: $showAdditionalInfo) {
                        if let cn = normalized(detail?.cn) {
                            infoRow(title: L10n.tr("official_info_cn"), value: cn)
                        }

                        if let substitutable = detail?.substitutableByGeneric {
                            infoRow(title: L10n.tr("aemps_generic_substitutable"), value: boolText(substitutable))
                        }

                        if let statusText {
                            infoRow(title: L10n.tr("aemps_status"), value: statusText)
                        }

                        if let dose = normalized(detail?.dosis) {
                            infoRow(title: L10n.tr("aemps_dose"), value: dose)
                        }

                        if let pharmaForm = normalized(detail?.simplifiedPharmaceuticalForm) {
                            infoRow(title: L10n.tr("aemps_pharma_form_simple"), value: pharmaForm)
                        }

                        if let routesText {
                            infoRow(title: L10n.tr("aemps_routes"), value: routesText)
                        }

                        if let excipientsText {
                            infoRow(title: L10n.tr("aemps_excipients"), value: excipientsText)
                        }

                        if !documentItems.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(L10n.tr("aemps_documents"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                ForEach(documentItems, id: \.title) { item in
                                    Button {
                                        documentSheetURL = AEMPSURLSheetItem(url: item.url)
                                    } label: {
                                        Label(item.title, systemImage: "doc.text")
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        if let atcText {
                            infoRow(title: L10n.tr("aemps_atc"), value: atcText)
                        }
                    }
                }
            }

            Section {
                Button {
                    showingAddTypeDialog = true
                } label: {
                    Text(L10n.tr("aemps_add_as_medication"))
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
        }
        .navigationTitle(L10n.tr("detail_title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(L10n.tr("button_close")) { dismiss() }
            }
        }
        .overlay {
            if showingAddTypeDialog {
                AEMPSAddMedicationTypeOverlay(
                    onChooseScheduled: {
                        showingAddTypeDialog = false
                        addMode = .scheduled
                    },
                    onChooseOccasional: {
                        showingAddTypeDialog = false
                        addMode = .occasional
                    },
                    onCancel: {
                        showingAddTypeDialog = false
                    }
                )
                .transition(.opacity)
                .zIndex(2)
            }
        }
        .sheet(item: $addMode) { mode in
            EditMedicationView(
                medication: nil,
                creationKind: mode.kind,
                markTakenNowOnCreate: false,
                initialStartDate: Date(),
                prefill: MedicationPrefillData(
                    name: suggestion.nombreConDosis,
                    note: nil,
                    photoData: imageData,
                    cimaNRegistro: suggestion.nregistro.isEmpty ? nil : suggestion.nregistro,
                    cimaCN: normalized(detail?.cn),
                    cimaNombreCompleto: normalized(detail?.nombreCompleto ?? suggestion.nombreCompleto),
                    cimaPrincipioActivo: normalized(detail?.principioActivo ?? suggestion.principioActivo),
                    cimaLaboratorio: normalized(detail?.laboratorio ?? suggestion.laboratorio),
                    cimaProspectoURL: detail?.prospectoURL?.absoluteString
                )
            )
        }
        .sheet(item: $documentSheetURL) { item in
            NavigationStack {
                AEMPSProspectoScreen(url: item.url)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(L10n.tr("button_close")) {
                                documentSheetURL = nil
                            }
                        }
                    }
            }
        }
        .onAppear {
            loadDetailIfNeeded()
        }
    }

    @ViewBuilder
    private func infoRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
        }
    }

    private func normalized(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func boolText(_ value: Bool) -> String {
        value ? L10n.tr("aemps_yes") : L10n.tr("aemps_no")
    }

    private var additionalInfoAvailable: Bool {
        guard let detail else { return false }
        return detail.substitutableByGeneric != nil ||
            normalized(detail.cn) != nil ||
            statusText != nil ||
            normalized(detail.dosis) != nil ||
            normalized(detail.simplifiedPharmaceuticalForm) != nil ||
            routesText != nil ||
            excipientsText != nil ||
            !documentItems.isEmpty ||
            atcText != nil
    }

    private var statusText: String? {
        guard let detail else { return nil }
        let parts = [
            detail.statusAuthorizedAt.map { String(format: L10n.tr("aemps_status_auth_format"), Fmt.dayMedium($0)) },
            detail.statusRevisionAt.map { String(format: L10n.tr("aemps_status_rev_format"), Fmt.dayMedium($0)) }
        ].compactMap { $0 }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " · ")
    }

    private var routesText: String? {
        guard let detail, !detail.administrationRoutes.isEmpty else { return nil }
        return detail.administrationRoutes.joined(separator: ", ")
    }

    private var excipientsText: String? {
        guard let detail, !detail.excipients.isEmpty else { return nil }
        return detail.excipients.joined(separator: ", ")
    }

    private var atcText: String? {
        guard let detail, !detail.atc.isEmpty else { return nil }
        return detail.atc.joined(separator: "\n")
    }

    private var documentItems: [(title: String, url: URL)] {
        guard let detail else { return [] }
        var items: [(title: String, url: URL)] = []
        if let ft = detail.technicalSheetURL {
            items.append((title: L10n.tr("aemps_document_technical_sheet"), url: ft))
        }
        if let leaflet = detail.prospectoURL {
            items.append((title: L10n.tr("aemps_document_leaflet"), url: leaflet))
        }
        if let report = detail.reportAndRisksURL {
            items.append((title: L10n.tr("aemps_document_report_risks"), url: report))
        }
        return items
    }

    private func loadDetailIfNeeded() {
        guard !suggestion.nregistro.isEmpty else { return }
        isLoadingDetail = true

        Task {
            let fetchedDetail = try? await cimaService.fetchMedicationDetail(nregistro: suggestion.nregistro)
            var fetchedImage: Data? = nil
            if let url = fetchedDetail?.imageURL {
                fetchedImage = try? await cimaService.fetchImageData(url: url)
            }

            await MainActor.run {
                detail = fetchedDetail
                if let fetchedImage, UIImage(data: fetchedImage) != nil {
                    imageData = fetchedImage
                }
                isLoadingDetail = false
            }
        }
    }

}

private struct AEMPSProspectoScreen: View {
    let url: URL

    var body: some View {
        AEMPSProspectoWebView(url: url)
            .navigationTitle(L10n.tr("official_info_leaflet_button"))
            .navigationBarTitleDisplayMode(.inline)
    }
}

private struct AEMPSProspectoWebView: UIViewRepresentable {
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

private struct AEMPSAddMedicationTypeOverlay: View {
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
