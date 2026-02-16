import SwiftUI
import UIKit

enum MedicationDefaultArtworkKind {
    case red
    case yellow
    case blue
}

enum MedicationDefaultArtwork {
    static let dailyChronicAssetName = "PastillaRoja"
    static let occasionalAssetName = "PastillaAmarilla"
    static let otherAssetName = "PastillaAzul"

    static func kind(for medication: Medication) -> MedicationDefaultArtworkKind {
        kind(
            kind: medication.kind,
            repeatUnit: medication.repeatUnit,
            interval: medication.interval,
            endDate: medication.endDate
        )
    }

    static func kind(kind: MedicationKind, repeatUnit: RepeatUnit, interval: Int, endDate: Date?) -> MedicationDefaultArtworkKind {
        if kind == .occasional { return .yellow }
        if repeatUnit == .day && interval == 1 && endDate == nil { return .red }
        return .blue
    }

    static func uiImage(for kind: MedicationDefaultArtworkKind) -> UIImage? {
        UIImage(named: assetName(for: kind))
    }

    private static func assetName(for kind: MedicationDefaultArtworkKind) -> String {
        switch kind {
        case .red: return dailyChronicAssetName
        case .yellow: return occasionalAssetName
        case .blue: return otherAssetName
        }
    }

    static func fallbackColor(for kind: MedicationDefaultArtworkKind) -> Color {
        switch kind {
        case .red: return AppTheme.brandRed
        case .yellow: return AppTheme.brandYellow
        case .blue: return AppTheme.brandBlue
        }
    }
}

struct MedicationDefaultArtworkView: View {
    let kind: MedicationDefaultArtworkKind
    let width: CGFloat?
    let height: CGFloat
    let cornerRadius: CGFloat

    var body: some View {
        Group {
            if let ui = MedicationDefaultArtwork.uiImage(for: kind) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
            } else {
                let color = MedicationDefaultArtwork.fallbackColor(for: kind)
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(color.opacity(0.14))
                    Image(systemName: "pills.fill")
                        .font(.system(size: max(14, height * 0.34), weight: .semibold))
                        .foregroundStyle(color)
                }
            }
        }
        .frame(maxWidth: width == nil ? .infinity : nil)
        .frame(width: width, height: height)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}
