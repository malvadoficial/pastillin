//
//  Formatters.swift
//  MediRecord
//
//  Created by José Manuel Rives on 11/2/26.
//

import Foundation

enum Fmt {
    static var locale: Locale {
        // Respeta el idioma del dispositivo y se actualiza si cambia
        .autoupdatingCurrent
        // Si quieres fijar siempre un idioma concreto, descomenta y ajusta:
        // Locale(identifier: "es_ES")
    }

    static func dayLong(_ date: Date) -> String {
        // Ejemplo: lunes, 11 de febrero de 2026
        let style = Date.FormatStyle(date: .complete, time: .omitted).locale(locale)
        return date.formatted(style)
    }

    static func dayMedium(_ date: Date) -> String {
        // Ejemplo: 11 feb 2026 (dependiendo de la región)
        let style = Date.FormatStyle(date: .abbreviated, time: .omitted).locale(locale)
        return date.formatted(style)
    }
    
    static func dateShort(_ date: Date) -> String {
        // Corto/medio según región (evita hardcodear patrones)
        let style = Date.FormatStyle(date: .abbreviated, time: .omitted).locale(locale)
        return date.formatted(style)
    }

    static func timeShort(_ date: Date) -> String {
        let style = Date.FormatStyle(date: .omitted, time: .shortened).locale(locale)
        return date.formatted(style)
    }

    static func monthTitle(_ date: Date) -> String {
        // Usa una plantilla localizada para evitar hardcodear "LLLL yyyy"
        let f = DateFormatter()
        f.locale = locale
        // "yMMMM" prioriza el nombre completo del mes con año (p.ej. "febrero de 2026")
        f.setLocalizedDateFormatFromTemplate("yMMMM")
        return f.string(from: date)
    }
}
