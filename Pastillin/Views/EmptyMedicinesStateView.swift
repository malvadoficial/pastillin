import SwiftUI
import UIKit

struct EmptyMedicinesStateView: View {
    private var localizedEmptyImageName: String {
        let preferred = Bundle.main.preferredLocalizations.first?.lowercased() ?? "en"
        if preferred.hasPrefix("es") {
            return "NoMedicines_ES"
        }
        return "NoMedicines_EN"
    }

    private var resolvedImageName: String? {
        if UIImage(named: localizedEmptyImageName) != nil {
            return localizedEmptyImageName
        }
        if UIImage(named: "NoMedicines_EN") != nil {
            return "NoMedicines_EN"
        }
        if UIImage(named: "EmptyMedicinesState") != nil {
            return "EmptyMedicinesState"
        }
        return nil
    }

    var body: some View {
        VStack(spacing: 12) {
            if let imageName = resolvedImageName {
                Image(imageName)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 420)
            } else {
                Image(systemName: "pills")
                    .font(.system(size: 46, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(L10n.tr("empty_medicines_fallback"))
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}
