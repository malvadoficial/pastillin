import Foundation
import Combine

struct CIMAMedicationSuggestion: Identifiable, Hashable {
    let nregistro: String
    let nombrePrincipal: String
    let dosis: String?
    let nombreCompleto: String?
    let principioActivo: String?
    let laboratorio: String?
    let prescriptionLabel: String?
    let requiresPrescription: Bool?
    let isCommercialized: Bool?
    let isAuthorized: Bool?

    nonisolated var id: String {
        nregistro.isEmpty ? nombrePrincipal : nregistro
    }

    nonisolated var nombreConDosis: String {
        guard let dosis, !dosis.isEmpty else { return nombrePrincipal }
        return "\(nombrePrincipal) · \(dosis)"
    }

    nonisolated var searchableText: String {
        [nombrePrincipal, dosis, nombreCompleto]
            .compactMap { $0 }
            .joined(separator: " ")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    }
}

struct CIMAMedicationDetail: Hashable {
    let nombreCompleto: String?
    let principioActivo: String?
    let laboratorio: String?
    let cn: String?
    let prospectoURL: URL?
    let technicalSheetURL: URL?
    let reportAndRisksURL: URL?
    let imageURL: URL?
    let prescriptionLabel: String?
    let requiresPrescription: Bool?
    let isCommercialized: Bool?
    let isAuthorized: Bool?
    let substitutableByGeneric: Bool?
    let statusAuthorizedAt: Date?
    let statusRevisionAt: Date?
    let excipients: [String]
    let dosis: String?
    let simplifiedPharmaceuticalForm: String?
    let administrationRoutes: [String]
    let atc: [String]
}

enum CIMASearchField: Int, CaseIterable, Identifiable {
    case name
    case activeIngredient
    case registration

    var id: Int { rawValue }
}

enum CIMAPrescriptionFilter: Int, CaseIterable, Identifiable {
    case indifferent
    case withPrescription
    case withoutPrescription

    var id: Int { rawValue }
}

struct CIMASearchFilters {
    var authorizedOnly: Bool
    var commercializedOnly: Bool
    var prescriptionFilter: CIMAPrescriptionFilter

    static let `default` = CIMASearchFilters(
        authorizedOnly: true,
        commercializedOnly: true,
        prescriptionFilter: .indifferent
    )
}

actor CIMAService {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchNameSuggestions(query: String, page: Int = 1, limit: Int = 6) async throws -> [CIMAMedicationSuggestion] {
        try await searchMedications(
            query: query,
            field: .name,
            filters: .default,
            page: page,
            limit: limit
        )
    }

    func searchMedications(
        query: String,
        field: CIMASearchField,
        filters: CIMASearchFilters,
        page: Int = 1,
        limit: Int = 25
    ) async throws -> [CIMAMedicationSuggestion] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        switch field {
        case .registration:
            guard !trimmed.isEmpty else { return [] }
        case .name, .activeIngredient:
            guard trimmed.count >= 3 else { return [] }
        }

        var components = URLComponents(string: "https://cima.aemps.es/cima/rest/medicamentos")
        var items: [URLQueryItem] = [
            URLQueryItem(name: "autorizados", value: filters.authorizedOnly ? "1" : "0"),
            URLQueryItem(name: "comerc", value: filters.commercializedOnly ? "1" : "0"),
            URLQueryItem(name: "pagina", value: String(max(1, page)))
        ]

        switch filters.prescriptionFilter {
        case .indifferent:
            break
        case .withPrescription:
            items.append(URLQueryItem(name: "conreceta", value: "1"))
        case .withoutPrescription:
            items.append(URLQueryItem(name: "conreceta", value: "0"))
        }

        switch field {
        case .name:
            items.append(URLQueryItem(name: "nombre", value: trimmed))
        case .activeIngredient:
            items.append(URLQueryItem(name: "pactivos", value: trimmed))
        case .registration:
            items.append(URLQueryItem(name: "nregistro", value: trimmed))
        }
        components?.queryItems = items

        guard let url = components?.url else { return [] }

        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            return []
        }

        let decoded: [CIMAMedicationDTO] = await MainActor.run {
            let decoder = JSONDecoder()
            if let wrapped = try? decoder.decode(CIMAMedicationListWrapped.self, from: data) {
                return wrapped.medicamentos ?? wrapped.resultados ?? wrapped.resultadosBusqueda ?? []
            }
            if let plain = try? decoder.decode([CIMAMedicationDTO].self, from: data) {
                return plain
            }
            return []
        }

        let prescriptionFiltered = decoded.filter { dto in
            switch filters.prescriptionFilter {
            case .indifferent:
                return true
            case .withPrescription:
                return dto.receta == true
            case .withoutPrescription:
                return dto.receta == false
            }
        }

        return Array(Self.mapMedicationSuggestions(prescriptionFiltered).prefix(limit))
    }

    func fetchMedicationDetail(nregistro: String) async throws -> CIMAMedicationDetail? {
        let trimmed = nregistro.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var components = URLComponents(string: "https://cima.aemps.es/cima/rest/medicamento")
        components?.queryItems = [
            URLQueryItem(name: "nregistro", value: trimmed)
        ]

        guard let url = components?.url else { return nil }

        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            return nil
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let principioActivo = Self.cleanOptionalText((json["pactivos"] as? String) ?? (json["principiosActivos"] as? String))
        let laboratorio = Self.cleanOptionalText((json["labtitular"] as? String) ?? (json["laboratorio"] as? String))
        let nombreCompleto = Self.cleanOptionalText(json["nombre"] as? String)
        let cn = Self.cleanOptionalText(((json["presentaciones"] as? [[String: Any]])?.first?["cn"] as? String))
        let technicalSheetURL = Self.findDocumentURL(in: json, type: 1)
        let prospectoURL = Self.findDocumentURL(in: json, type: 2) ?? Self.findProspectoURL(in: json)
        let reportAndRisksURL = Self.findDocumentURL(in: json, type: 3)
        let imageURL = Self.findMedicationImageURL(in: json)
        let prescriptionLabel = Self.cleanOptionalText(json["cpresc"] as? String)
        let requiresPrescription = json["receta"] as? Bool
        let isCommercialized = json["comerc"] as? Bool
        let substitutableByGeneric: Bool? = {
            guard let noSust = json["nosustituible"] as? [String: Any] else { return nil }
            if let id = noSust["id"] as? Int { return id == 0 }
            if let idNumber = noSust["id"] as? NSNumber { return idNumber.intValue == 0 }
            return nil
        }()
        let statusAuthorizedAt = Self.parseStatusDate(in: json, key: "aut")
        let statusRevisionAt = Self.parseStatusDate(in: json, key: "rev")
        let excipients = Self.parseNamedItems(in: json["excipientes"], key: "nombre")
        let dosis = Self.cleanOptionalText(json["dosis"] as? String)
        let simplifiedPharmaceuticalForm = Self.cleanOptionalText((json["formaFarmaceuticaSimplificada"] as? [String: Any])?["nombre"] as? String)
        let administrationRoutes = Self.parseNamedItems(in: json["viasAdministracion"], key: "nombre")
        let atc = Self.parseATC(in: json["atcs"])
        let isAuthorized: Bool? = {
            guard let estado = json["estado"] as? [String: Any] else { return nil }
            if estado["aut"] is NSNumber || estado["aut"] is String {
                return true
            }
            return nil
        }()

        if nombreCompleto == nil,
           principioActivo == nil,
           laboratorio == nil,
           cn == nil,
           prospectoURL == nil,
           technicalSheetURL == nil,
           reportAndRisksURL == nil,
           imageURL == nil,
           prescriptionLabel == nil,
           requiresPrescription == nil,
           isCommercialized == nil,
           isAuthorized == nil,
           substitutableByGeneric == nil,
           statusAuthorizedAt == nil,
           statusRevisionAt == nil,
           excipients.isEmpty,
           dosis == nil,
           simplifiedPharmaceuticalForm == nil,
           administrationRoutes.isEmpty,
           atc.isEmpty {
            return nil
        }

        return CIMAMedicationDetail(
            nombreCompleto: nombreCompleto,
            principioActivo: principioActivo,
            laboratorio: laboratorio,
            cn: cn,
            prospectoURL: prospectoURL,
            technicalSheetURL: technicalSheetURL,
            reportAndRisksURL: reportAndRisksURL,
            imageURL: imageURL,
            prescriptionLabel: prescriptionLabel,
            requiresPrescription: requiresPrescription,
            isCommercialized: isCommercialized,
            isAuthorized: isAuthorized,
            substitutableByGeneric: substitutableByGeneric,
            statusAuthorizedAt: statusAuthorizedAt,
            statusRevisionAt: statusRevisionAt,
            excipients: excipients,
            dosis: dosis,
            simplifiedPharmaceuticalForm: simplifiedPharmaceuticalForm,
            administrationRoutes: administrationRoutes,
            atc: atc
        )
    }

    func fetchImageData(url: URL) async throws -> Data? {
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode), !data.isEmpty else {
            return nil
        }
        return data
    }

    private static func extractMainName(from fullName: String) -> String {
        // 1) quitar contenido entre paréntesis
        let noParens = fullName.replacingOccurrences(of: "\\s*\\(.*?\\)", with: "", options: .regularExpression)

        // 2) cortar desde dosis/forma/composición habitual
        let stopTokens = [
            #"\b\d+(?:[\.,]\d+)?\s*(mg|mcg|g|ml|ui|iu|%|mclg|ug)\b"#,
            #"\b(comprimidos?|capsulas?|c[aá]psulas?|soluci[oó]n|jarabe|inyectable|parches?|suspensi[oó]n|granulado|crema|gel|pomada|gotas?)\b"#,
            #"\b(efg|liberaci[oó]n|prolongada|retard|forte)\b"#
        ]

        var cutIndex = noParens.endIndex
        for pattern in stopTokens {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(noParens.startIndex..<noParens.endIndex, in: noParens)
                if let match = regex.firstMatch(in: noParens, options: [], range: range),
                   let r = Range(match.range, in: noParens),
                   r.lowerBound < cutIndex {
                    cutIndex = r.lowerBound
                }
            }
        }

        var main = String(noParens[..<cutIndex])

        // 3) limpiar separadores comunes
        if let comma = main.firstIndex(of: ",") { main = String(main[..<comma]) }
        if let slash = main.firstIndex(of: "/") { main = String(main[..<slash]) }

        main = main
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)

        // 4) normalizar estilo (Title Case suave)
        return main.capitalized
    }

    private static func cleanOptionalText(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func mapMedicationSuggestions(_ items: [CIMAMedicationDTO]) -> [CIMAMedicationSuggestion] {
        let mapped = items.compactMap { dto -> CIMAMedicationSuggestion? in
            let raw = (dto.nombre ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty else { return nil }

            let main = Self.extractMainName(from: raw)
            guard !main.isEmpty else { return nil }

            return CIMAMedicationSuggestion(
                nregistro: dto.nregistro ?? "",
                nombrePrincipal: main,
                dosis: Self.cleanOptionalText(dto.dosis),
                nombreCompleto: Self.cleanOptionalText(dto.nombre),
                principioActivo: Self.cleanOptionalText(dto.pactivos),
                laboratorio: Self.cleanOptionalText(dto.labtitular),
                prescriptionLabel: Self.cleanOptionalText(dto.cpresc),
                requiresPrescription: dto.receta,
                isCommercialized: dto.comerc,
                isAuthorized: dto.estado?.aut != nil
            )
        }

        var seen = Set<String>()
        return mapped.filter { item in
            let base = item.nregistro.isEmpty ? item.nombreConDosis : item.nregistro
            let key = base.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            if seen.contains(key) { return false }
            seen.insert(key)
            return true
        }
    }

    private static func findProspectoURL(in object: Any) -> URL? {
        if let dict = object as? [String: Any] {
            if let docs = dict["docs"] as? [[String: Any]] {
                if let prospectoDoc = docs.first(where: { ($0["tipo"] as? Int) == 2 }) {
                    if let html = prospectoDoc["urlHtml"] as? String,
                       let url = parseWebURL(html),
                       isProspectoURL(url) {
                        return url
                    }
                    if let pdf = prospectoDoc["url"] as? String,
                       let url = parseWebURL(pdf),
                       isProspectoURL(url) {
                        return url
                    }
                }
            }

            // Prioriza claves típicas de prospecto.
            let preferredKeys = [
                "urlProspecto",
                "urlProspectoPdf",
                "urlPdfProspecto",
                "prospecto",
                "urlHtmlProspecto",
                "url"
            ]
            for key in preferredKeys {
                if let value = dict[key] as? String,
                   let url = parseWebURL(value),
                   isProspectoURL(url) {
                    return url
                }
            }
            for (_, value) in dict {
                if let url = findProspectoURL(in: value) {
                    return url
                }
            }
        } else if let array = object as? [Any] {
            for value in array {
                if let url = findProspectoURL(in: value) {
                    return url
                }
            }
        } else if let text = object as? String,
                  let url = parseWebURL(text),
                  isProspectoURL(url) {
            return url
        }
        return nil
    }

    private static func parseWebURL(_ rawValue: String) -> URL? {
        let raw = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }

        if let url = URL(string: raw),
           let scheme = url.scheme,
           (scheme == "http" || scheme == "https") {
            return url
        }

        if raw.hasPrefix("www.") || raw.hasPrefix("cima.aemps.es") {
            return URL(string: "https://\(raw)")
        }
        return nil
    }

    private static func parseStatusDate(in json: [String: Any], key: String) -> Date? {
        guard let estado = json["estado"] as? [String: Any] else { return nil }
        if let millis = estado[key] as? NSNumber {
            return Date(timeIntervalSince1970: millis.doubleValue / 1000.0)
        }
        if let millisText = estado[key] as? String,
           let millis = Double(millisText) {
            return Date(timeIntervalSince1970: millis / 1000.0)
        }
        return nil
    }

    private static func parseNamedItems(in object: Any?, key: String) -> [String] {
        guard let array = object as? [[String: Any]] else { return [] }
        return array.compactMap { item in
            cleanOptionalText(item[key] as? String)
        }
    }

    private static func parseATC(in object: Any?) -> [String] {
        guard let array = object as? [[String: Any]] else { return [] }
        return array.compactMap { item in
            let code = cleanOptionalText(item["codigo"] as? String)
            let name = cleanOptionalText(item["nombre"] as? String)
            if let code, let name { return "\(code) · \(name)" }
            return code ?? name
        }
    }

    private static func findDocumentURL(in object: Any, type: Int) -> URL? {
        guard let dict = object as? [String: Any],
              let docs = dict["docs"] as? [[String: Any]] else {
            return nil
        }
        guard let doc = docs.first(where: { ($0["tipo"] as? Int) == type || ($0["tipo"] as? NSNumber)?.intValue == type }) else {
            return nil
        }
        if let html = doc["urlHtml"] as? String, let url = parseWebURL(html) {
            return url
        }
        if let pdf = doc["url"] as? String, let url = parseWebURL(pdf) {
            return url
        }
        return nil
    }

    private static func parseImageURL(_ rawValue: String) -> URL? {
        guard let url = parseWebURL(rawValue) else { return nil }
        let text = url.absoluteString.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let isImageExtension = text.hasSuffix(".jpg") || text.hasSuffix(".jpeg") || text.hasSuffix(".png") || text.hasSuffix(".webp")
        let isCIMAFoto = text.contains("/cima/fotos/")
        return (isImageExtension || isCIMAFoto) ? url : nil
    }

    private static func findMedicationImageURL(in object: Any) -> URL? {
        if let dict = object as? [String: Any] {
            if let fotos = dict["fotos"] as? [[String: Any]] {
                // Prioriza "materialas" (caja real) y usa primera imagen válida como fallback.
                if let preferred = fotos.first(where: {
                    (($0["tipo"] as? String)?.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).contains("material") ?? false)
                }),
                   let raw = preferred["url"] as? String,
                   let url = parseImageURL(raw) {
                    return url
                }
                for item in fotos {
                    if let raw = item["url"] as? String,
                       let url = parseImageURL(raw) {
                        return url
                    }
                }
            }

            let preferredKeys = ["urlFoto", "foto", "imagen", "image", "thumbnail", "thumb"]
            for key in preferredKeys {
                if let raw = dict[key] as? String,
                   let url = parseImageURL(raw) {
                    return url
                }
            }

            for (_, value) in dict {
                if let url = findMedicationImageURL(in: value) {
                    return url
                }
            }
        } else if let array = object as? [Any] {
            for value in array {
                if let url = findMedicationImageURL(in: value) {
                    return url
                }
            }
        } else if let text = object as? String,
                  let url = parseImageURL(text) {
            return url
        }
        return nil
    }

    private static func isProspectoURL(_ url: URL) -> Bool {
        let text = url.absoluteString.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        if text.contains("prospecto") {
            return true
        }
        if text.contains("/cima/pdfs/p/") || text.contains("/cima/dochtml/p/") {
            return true
        }
        return false
    }
}

@MainActor
final class MedicationNameAutocompleteViewModel: ObservableObject {
    @Published private(set) var suggestions: [CIMAMedicationSuggestion] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var didSearch: Bool = false

    private let service: CIMAService
    private var searchTask: Task<Void, Never>?
    private var latestQuery: String = ""

    // Cache por prefijo
    private var cache: [String: [CIMAMedicationSuggestion]] = [:]

    init(service: CIMAService = CIMAService()) {
        self.service = service
    }

    func updateQuery(_ raw: String) {
        let query = Self.normalize(raw)
        latestQuery = query

        guard query.count >= 3 else {
            clearResults(resetSearchState: true)
            return
        }

        if let exact = cache[query] {
            suggestions = exact
            isLoading = false
            didSearch = true
            return
        }

        // Si tenemos caché de un prefijo más corto, la usamos provisionalmente
        if let prefixKey = cache.keys
            .filter({ query.hasPrefix($0) })
            .max(by: { $0.count < $1.count }),
           let pref = cache[prefixKey] {
            let provisional = pref.filter {
                $0.searchableText.contains(query)
            }
            if !provisional.isEmpty {
                suggestions = provisional
                didSearch = true
            }
        }

        searchTask?.cancel()
        searchTask = Task { [weak self] in
            guard let self else { return }

            try? await Task.sleep(nanoseconds: 450_000_000) // debounce 450ms
            guard !Task.isCancelled else { return }

            await MainActor.run {
                self.isLoading = true
            }

            do {
                let result = try await self.service.fetchNameSuggestions(query: query, page: 1)
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    guard self.latestQuery == query else { return }
                    self.cache[query] = result
                    self.suggestions = result
                    self.isLoading = false
                    self.didSearch = true
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard self.latestQuery == query else { return }
                    self.suggestions = []
                    self.isLoading = false
                    self.didSearch = true
                }
            }
        }
    }

    func clearResults(resetSearchState: Bool = false) {
        searchTask?.cancel()
        searchTask = nil
        suggestions = []
        isLoading = false
        if resetSearchState {
            didSearch = false
        }
    }

    func cancel() {
        searchTask?.cancel()
    }

    private static func normalize(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    }
}

private struct CIMAMedicationListWrapped: Decodable {
    let medicamentos: [CIMAMedicationDTO]?
    let resultados: [CIMAMedicationDTO]?
    let resultadosBusqueda: [CIMAMedicationDTO]?
}

private struct CIMAMedicationDTO: Decodable {
    let nregistro: String?
    let nombre: String?
    let dosis: String?
    let pactivos: String?
    let labtitular: String?
    let cpresc: String?
    let receta: Bool?
    let comerc: Bool?
    let estado: CIMAEstadoDTO?
}

private struct CIMAEstadoDTO: Decodable {
    let aut: Double?
}
