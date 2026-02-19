import SwiftUI
import SwiftData
import UIKit

struct ShoppingCartView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var medications: [Medication]
    @State private var showShareSheet = false
    @State private var listEditMode: EditMode = .inactive
    private let emptyArtworkHeight: CGFloat = 180

    private var cartMeds: [Medication] {
        medications
            .filter { $0.inShoppingCart }
            .sorted { lhs, rhs in
                switch (lhs.shoppingCartSortOrder, rhs.shoppingCartSortOrder) {
                case let (l?, r?):
                    if l != r { return l < r }
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    break
                }

                switch (lhs.shoppingCartExpectedEndDate, rhs.shoppingCartExpectedEndDate) {
                case let (l?, r?):
                    if l != r { return l < r }
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    break
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    private var canShareList: Bool {
        !cartMeds.isEmpty
    }

    private var shareListText: String {
        let items = cartMeds.map { med in
            if let expectedEnd = med.estimatedRunOutDate() {
                return String(
                    format: L10n.tr("cart_share_item_with_date_format"),
                    med.name,
                    Fmt.dayMedium(expectedEnd)
                )
            }
            return "- \(med.name)"
        }
        return ([L10n.tr("cart_share_intro")] + items).joined(separator: "\n")
    }

    var body: some View {
        List {
            if cartMeds.isEmpty {
                Section {
                    VStack(spacing: 10) {
                        cartEmptyStateArtwork

                        Text(L10n.tr("cart_empty"))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .padding(.vertical, 8)
                }
            } else {
                ForEach(cartMeds) { med in
                    VStack(spacing: 10) {
                        HStack(spacing: 12) {
                            medicationThumbnail(for: med)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(med.name)
                                    .font(.subheadline.weight(.semibold))
                                if med.shoppingCartRemainingDoses == 0 {
                                    Text(L10n.tr("cart_expected_end_out_of_stock"))
                                        .font(.footnote.weight(.semibold))
                                        .foregroundStyle(AppTheme.brandRed)
                                } else if let expectedEnd = med.estimatedRunOutDate() {
                                    Text(String(format: L10n.tr("cart_expected_end_format"), Fmt.dayMedium(expectedEnd)))
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text(L10n.tr("cart_expected_end_unknown"))
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer()

                            Button(role: .destructive) {
                                med.inShoppingCart = false
                                med.shoppingCartRemainingDoses = nil
                                med.shoppingCartSortOrder = nil
                                try? modelContext.save()
                            } label: {
                                Image(systemName: "trash")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .buttonStyle(.plain)
                        }

                        HStack(spacing: 8) {
                            Text(L10n.tr("cart_remaining_doses"))
                                .foregroundStyle(.secondary)

                            Spacer(minLength: 10)

                            HStack(spacing: 8) {
                                Button {
                                    decrementRemainingDoses(for: med)
                                } label: {
                                    Image(systemName: "minus")
                                        .font(.caption.weight(.bold))
                                        .frame(width: 24, height: 24)
                                        .background(
                                            Circle()
                                                .fill(AppTheme.brandYellow.opacity(0.22))
                                        )
                                }
                                .buttonStyle(.plain)

                                TextField(
                                    L10n.tr("cart_remaining_doses_placeholder"),
                                    text: remainingDosesTextBinding(for: med)
                                )
                                .multilineTextAlignment(.center)
                                .keyboardType(.numberPad)
                                .frame(width: 56)

                                Button {
                                    incrementRemainingDoses(for: med)
                                } label: {
                                    Image(systemName: "plus")
                                        .font(.caption.weight(.bold))
                                        .frame(width: 24, height: 24)
                                        .background(
                                            Circle()
                                                .fill(AppTheme.brandYellow.opacity(0.22))
                                        )
                                }
                                .buttonStyle(.plain)
                            }

                            Spacer(minLength: 10)

                            if med.shoppingCartRemainingDoses != nil {
                                Button {
                                    med.shoppingCartRemainingDoses = nil
                                    try? modelContext.save()
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(AppTheme.brandRed)
                                        .frame(width: 24, height: 24)
                                        .background(
                                            Circle()
                                                .fill(AppTheme.brandRed.opacity(0.18))
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        Button {
                            med.inShoppingCart = false
                            med.shoppingCartRemainingDoses = nil
                            med.shoppingCartSortOrder = nil
                            try? modelContext.save()
                        } label: {
                            Text(L10n.tr("cart_mark_purchased"))
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppTheme.brandYellow)
                    }
                    .padding(.vertical, 6)
                }
                .onMove(perform: moveCartItems)
            }
        }
        .environment(\.editMode, $listEditMode)
        .navigationTitle(L10n.tr("cart_title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    withAnimation {
                        listEditMode = (listEditMode == .active) ? .inactive : .active
                    }
                } label: {
                    Image(systemName: (listEditMode == .active) ? "checkmark" : "pencil")
                }
                .accessibilityLabel(L10n.tr("button_edit"))
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                if canShareList {
                    Button {
                        showShareSheet = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel(L10n.tr("cart_share_button"))
                }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            ActivityShareView(activityItems: [shareListText])
        }
    }

    @ViewBuilder
    private var cartEmptyStateArtwork: some View {
        let localeCode = Locale.current.language.languageCode?.identifier.lowercased() ?? "es"
        let preferredAssetName = localeCode.hasPrefix("en") ? "ShoppingCartEmptyState_EN" : "ShoppingCartEmptyState_ES"

        if UIImage(named: preferredAssetName) != nil {
            Image(preferredAssetName)
                .resizable()
                .scaledToFit()
                .frame(height: emptyArtworkHeight)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            Image(systemName: "cart")
                .font(.system(size: 62, weight: .semibold))
                .foregroundStyle(.secondary.opacity(0.8))
                .frame(maxWidth: .infinity)
        }
    }

    private func remainingDosesTextBinding(for medication: Medication) -> Binding<String> {
        Binding(
            get: {
                if let value = medication.shoppingCartRemainingDoses {
                    return String(value)
                }
                return ""
            },
            set: { newValue in
                let digitsOnly = newValue.filter(\.isNumber)
                if let value = Int(digitsOnly), value >= 0 {
                    medication.shoppingCartRemainingDoses = value
                } else {
                    medication.shoppingCartRemainingDoses = nil
                }
                try? modelContext.save()
            }
        )
    }

    private func incrementRemainingDoses(for medication: Medication) {
        let current = medication.shoppingCartRemainingDoses ?? 0
        medication.shoppingCartRemainingDoses = min(current + 1, 9999)
        try? modelContext.save()
    }

    private func decrementRemainingDoses(for medication: Medication) {
        let current = medication.shoppingCartRemainingDoses ?? 0
        if current <= 0 {
            medication.shoppingCartRemainingDoses = nil
        } else {
            medication.shoppingCartRemainingDoses = current - 1
        }
        try? modelContext.save()
    }

    private func moveCartItems(from source: IndexSet, to destination: Int) {
        var ordered = cartMeds
        ordered.move(fromOffsets: source, toOffset: destination)
        for (idx, med) in ordered.enumerated() {
            med.shoppingCartSortOrder = idx
        }
        try? modelContext.save()
    }

    @ViewBuilder
    private func medicationThumbnail(for medication: Medication) -> some View {
        if let data = medication.photoData,
           let ui = UIImage(data: data) {
            Image(uiImage: ui)
                .resizable()
                .scaledToFill()
                .frame(width: 40, height: 40)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            MedicationDefaultArtworkView(
                kind: MedicationDefaultArtwork.kind(for: medication),
                width: 40,
                height: 40,
                cornerRadius: 8
            )
        }
    }
}

private struct ActivityShareView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
