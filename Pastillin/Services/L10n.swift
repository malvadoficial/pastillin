import Foundation

enum L10n {
    static func tr(_ key: String, _ args: CVarArg...) -> String {
        let format = NSLocalizedString(key, comment: "")
        if args.isEmpty {
            return format
        }
        return String(format: format, locale: Locale.autoupdatingCurrent, arguments: args)
    }

    static func unitDay(_ value: Int) -> String {
        value == 1 ? tr("unit_day_one") : tr("unit_day_other")
    }

    static func unitMonth(_ value: Int) -> String {
        value == 1 ? tr("unit_month_one") : tr("unit_month_other")
    }

    static func recurrenceText(repeatUnit: RepeatUnit, interval: Int) -> String {
        let safeInterval = max(1, interval)

        switch repeatUnit {
        case .day:
            if safeInterval == 1 { return tr("recurrence_daily") }
            return String(format: tr("recurrence_every_days_format"), safeInterval)
        case .month:
            if safeInterval == 1 { return tr("recurrence_monthly") }
            return String(format: tr("recurrence_every_months_format"), safeInterval)
        }
    }
}
