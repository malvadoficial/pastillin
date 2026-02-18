import SwiftUI

struct PendingIntakesIconView: View {
    let count: Int

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 17, weight: .semibold))
                .padding(.top, 3)
                .padding(.trailing, 4)

            if count > 0 {
                Text("\(count)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(
                        Capsule(style: .continuous)
                            .fill(AppTheme.brandRed)
                    )
                    .offset(x: 6, y: -3)
            }
        }
        .frame(width: 34, height: 28, alignment: .topTrailing)
        .contentShape(Rectangle())
        .accessibilityLabel(L10n.tr("tab_not_taken"))
        .accessibilityValue(count > 0 ? "\(count)" : "0")
    }
}
