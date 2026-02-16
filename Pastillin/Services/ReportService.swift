import Foundation
import SwiftData
import UIKit

enum ReportService {
    static func generatePDF(
        from start: Date,
        to end: Date,
        modelContext: ModelContext
    ) throws -> URL {
        let cal = Calendar.current
        let startKey = cal.startOfDay(for: start)
        let endKey = cal.startOfDay(for: end)

        let medsAll = try modelContext.fetch(FetchDescriptor<Medication>())
        let meds = medsAll.filter { $0.isActive }

        let logs = try modelContext.fetch(FetchDescriptor<IntakeLog>())

        // Index logs by (dateKey, medID)
        var dict: [String: IntakeLog] = [:]
        for log in logs {
            let dk = cal.startOfDay(for: log.dateKey)
            dict[key(dk, log.medicationID)] = log
        }

        let pageRect = CGRect(x: 0, y: 0, width: 595, height: 842) // A4 aprox
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)

        let filename = "\(L10n.tr("report_filename_prefix"))_\(Int(Date().timeIntervalSince1970)).pdf"
        let outURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

        let data = renderer.pdfData { ctx in
            ctx.beginPage()

            let topMargin: CGFloat = 40
            let bottomLimit: CGFloat = 800
            var y: CGFloat = topMargin

            func draw(_ text: String, font: UIFont, x: CGFloat = 40) {
                if y + font.lineHeight + 6 > bottomLimit {
                    ctx.beginPage()
                    y = topMargin
                }
                let attrs: [NSAttributedString.Key: Any] = [.font: font]
                text.draw(at: CGPoint(x: x, y: y), withAttributes: attrs)
                y += font.lineHeight + 6
            }

            func normalized(_ value: String?) -> String? {
                guard let value else { return nil }
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }

            func drawOfficialInfo(for med: Medication) {
                let fullName = normalized(med.cimaNombreCompleto)
                let activeIngredient = normalized(med.cimaPrincipioActivo)
                let laboratory = normalized(med.cimaLaboratorio)
                let hasOfficialInfo = normalized(med.cimaNombreCompleto) != nil || activeIngredient != nil || laboratory != nil

                guard hasOfficialInfo else { return }

                let infoFont = UIFont.systemFont(ofSize: 11)
                let infoX: CGFloat = 58

                if let fullName {
                    draw("· \(L10n.tr("official_info_full_name")): \(fullName)", font: infoFont, x: infoX)
                }
                if let activeIngredient {
                    draw("· \(L10n.tr("official_info_active_ingredient")): \(activeIngredient)", font: infoFont, x: infoX)
                }
                if let laboratory {
                    draw("· \(L10n.tr("official_info_laboratory")): \(laboratory)", font: infoFont, x: infoX)
                }
                draw("· \(L10n.tr("official_info_source")): \(L10n.tr("official_info_source_value"))", font: infoFont, x: infoX)
            }

            draw(L10n.tr("report_title"), font: .systemFont(ofSize: 24, weight: .semibold))
            draw(String(format: L10n.tr("report_period_format"), Fmt.dayMedium(startKey), Fmt.dayMedium(endKey)), font: .systemFont(ofSize: 12))
            y += 8

            let sortedMeds = meds.sorted {
                let o0 = $0.sortOrder ?? 0
                let o1 = $1.sortOrder ?? 0
                if o0 != o1 { return o0 < o1 }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }

            let chronicMeds = sortedMeds.filter { $0.kind == .scheduled && $0.endDate == nil }
            let scheduledFiniteMeds = sortedMeds.filter { $0.kind == .scheduled && $0.endDate != nil }
            let occasionalMeds = sortedMeds.filter { $0.kind == .occasional }

            draw(L10n.tr("report_general_title"), font: .boldSystemFont(ofSize: 14))

            draw(L10n.tr("report_general_chronic_section"), font: .boldSystemFont(ofSize: 12))
            if chronicMeds.isEmpty {
                draw("• \(L10n.tr("report_general_empty"))", font: .systemFont(ofSize: 12))
            } else {
                for med in chronicMeds {
                    let line = String(
                        format: L10n.tr("report_general_line_chronic"),
                        med.name,
                        Fmt.dayMedium(med.startDate)
                    )
                    draw("• \(line)", font: .systemFont(ofSize: 12))
                    drawOfficialInfo(for: med)
                }
            }

            draw(L10n.tr("report_general_scheduled_section"), font: .boldSystemFont(ofSize: 12))
            if scheduledFiniteMeds.isEmpty {
                draw("• \(L10n.tr("report_general_empty"))", font: .systemFont(ofSize: 12))
            } else {
                for med in scheduledFiniteMeds {
                    guard let endDate = med.endDate else { continue }
                    let line = String(
                        format: L10n.tr("report_general_line_scheduled"),
                        med.name,
                        Fmt.dayMedium(med.startDate),
                        Fmt.dayMedium(endDate)
                    )
                    draw("• \(line)", font: .systemFont(ofSize: 12))
                    drawOfficialInfo(for: med)
                }
            }

            draw(L10n.tr("report_general_occasional_section"), font: .boldSystemFont(ofSize: 12))
            if occasionalMeds.isEmpty {
                draw("• \(L10n.tr("report_general_empty"))", font: .systemFont(ofSize: 12))
            } else {
                for med in occasionalMeds {
                    let dayKey = cal.startOfDay(for: med.startDate)
                    let log = dict[key(dayKey, med.id)]
                    let line: String
                    if let takenAt = log?.takenAt {
                        line = String(
                            format: L10n.tr("report_general_line_occasional_with_time"),
                            med.name,
                            Fmt.dayMedium(med.startDate),
                            Fmt.timeShort(takenAt)
                        )
                    } else {
                        line = String(
                            format: L10n.tr("report_general_line_occasional"),
                            med.name,
                            Fmt.dayMedium(med.startDate)
                        )
                    }
                    draw("• \(line)", font: .systemFont(ofSize: 12))
                    drawOfficialInfo(for: med)
                }
            }

            y += 18
            draw(L10n.tr("report_daily_section_title"), font: .boldSystemFont(ofSize: 14))
            y += 2

            var day = startKey
            while day <= endKey {
                let dueMeds = meds.filter { $0.isDue(on: day, calendar: cal) }
                if !dueMeds.isEmpty {
                    draw(String(format: L10n.tr("report_day_format"), Fmt.dayLong(day)), font: .boldSystemFont(ofSize: 14))

                    for med in dueMeds.sorted(by: {
                        let o0 = $0.sortOrder ?? 0
                        let o1 = $1.sortOrder ?? 0
                        if o0 != o1 { return o0 < o1 }
                        return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                    }) {
                        let log = dict[key(day, med.id)]
                        let taken = (log?.isTaken == true)
                        let status = taken ? L10n.tr("report_taken") : L10n.tr("report_not_taken")
                        let medName: String
                        if med.kind == .occasional && taken {
                            medName = "\(med.name) (\(L10n.tr("report_occasional_badge")))"
                        } else {
                            medName = med.name
                        }

                        let line: String
                        if let takenAt = log?.takenAt {
                            line = String(
                                format: L10n.tr("report_line_with_time_format"),
                                medName,
                                status,
                                Fmt.timeShort(takenAt)
                            )
                        } else {
                            line = String(format: L10n.tr("report_line_format"), medName, status)
                        }
                        draw(line, font: .systemFont(ofSize: 12))
                    }
                    y += 6
                }

                day = cal.date(byAdding: .day, value: 1, to: day)!
            }
        }

        try data.write(to: outURL, options: .atomic)
        return outURL
    }

    private static func key(_ dayKey: Date, _ medID: UUID) -> String {
        "\(Int(dayKey.timeIntervalSince1970))_\(medID.uuidString)"
    }
}
