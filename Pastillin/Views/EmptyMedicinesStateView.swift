import SwiftUI
import UIKit

struct EmptyMedicinesStateView: View {
    private let unifiedImageName = "EmptyMedicinesState"

    var body: some View {
        VStack(spacing: 12) {
            if UIImage(named: unifiedImageName) != nil {
                Image(unifiedImageName)
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
