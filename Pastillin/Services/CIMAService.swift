import Foundation
import Combine

struct CIMAMedicationSuggestion: Identifiable, Hashable {
    let nregistro: String
    let nombrePrincipal: String
    let dosis: String?
    let nombreCompleto: String?
    let principioActivo: String?
    let laboratorio: String?

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
    let prospectoURL: URL?
    let imageURL: URL?
}

actor CIMAService {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchNameSuggestions(query: String, page: Int = 1, limit: Int = 6) async throws -> [CIMAMedicationSuggestion] {
        guard query.count >= 3 else { return [] }

        var components = URLComponents(string: "https://cima.aemps.es/cima/rest/medicamentos")
        components?.queryItems = [
            URLQueryItem(name: "nombre", value: query),
            URLQueryItem(name: "autorizados", value: "1"),
            URLQueryItem(name: "comerc", value: "1"),
            URLQueryItem(name: "pagina", value: String(max(1, page)))
        ]

        guard let url = components?.url else { return [] }

        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            return []
        }

        let items: [CIMAMedicationDTO] = await MainActor.run {
            let decoder = JSONDecoder()
            if let wrapped = try? decoder.decode(CIMAMedicationListWrapped.self, from: data) {
                return wrapped.medicamentos ?? wrapped.resultados ?? wrapped.resultadosBusqueda ?? []
            }
            if let plain = try? decoder.decode([CIMAMedicationDTO].self, from: data) {
                return plain
            }
            return []
        }

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
                laboratorio: Self.cleanOptionalText(dto.labtitular)
            )
        }

        // Dedupe por combinación visible (nombre + dosis), para no perder variantes de dosis.
        var seen = Set<String>()
        let unique = mapped.filter { item in
            let key = item.nombreConDosis.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            if seen.contains(key) { return false }
            seen.insert(key)
            return true
        }

        return Array(unique.prefix(limit))
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
        let prospectoURL = Self.findProspectoURL(in: json)
        let imageURL = Self.findMedicationImageURL(in: json)

        if nombreCompleto == nil, principioActivo == nil, laboratorio == nil, prospectoURL == nil, imageURL == nil {
            return nil
        }

        return CIMAMedicationDetail(
            nombreCompleto: nombreCompleto,
            principioActivo: principioActivo,
            laboratorio: laboratorio,
            prospectoURL: prospectoURL,
            imageURL: imageURL
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
}
