import SwiftUI

struct LegalDisclaimerView: View {
    let isMandatory: Bool
    let onAccept: (() -> Void)?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(L10n.tr("legal_disclaimer_intro"))
                        .font(.body)

                    disclaimerItem(L10n.tr("legal_disclaimer_point_1"))
                    disclaimerItem(L10n.tr("legal_disclaimer_point_2"))
                    disclaimerItem(L10n.tr("legal_disclaimer_point_3"))
                    disclaimerItem(L10n.tr("legal_disclaimer_point_4"))
                    disclaimerItem(L10n.tr("legal_disclaimer_point_5"))
                    disclaimerItem(L10n.tr("legal_disclaimer_point_6"))

                    Text(L10n.tr("legal_disclaimer_privacy_title"))
                        .font(.headline)
                        .padding(.top, 6)

                    Text(L10n.tr("legal_disclaimer_privacy_updated"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text(L10n.tr("legal_disclaimer_privacy_content"))
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)

                    if isMandatory {
                        Button {
                            onAccept?()
                        } label: {
                            Text(L10n.tr("legal_disclaimer_accept"))
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.top, 8)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
            .safeAreaPadding(.bottom, 84)
            .navigationTitle(L10n.tr("legal_disclaimer_title"))
            .navigationBarTitleDisplayMode(.inline)
        }
        .interactiveDismissDisabled(isMandatory)
    }

    @ViewBuilder
    private func disclaimerItem(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .font(.body.weight(.bold))
            Text(text)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
