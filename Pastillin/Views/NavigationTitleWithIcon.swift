import SwiftUI

struct NavigationTitleWithIcon: View {
    let title: String
    let systemImage: String
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(color)
            Text(title)
                .foregroundStyle(.primary)
        }
        .font(.headline.weight(.semibold))
    }
}
