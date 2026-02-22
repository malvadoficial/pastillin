import SwiftUI

struct HelpView: View {
    var body: some View {
        List {
            Section {
                Text(L10n.tr("help_intro"))
                    .font(.body)
                    .foregroundStyle(.primary)
            }

            Section(L10n.tr("help_section_tabs")) {
                helpRow(
                    title: L10n.tr("help_tab_today_title"),
                    text: L10n.tr("help_tab_today_text")
                )
                helpRow(
                    title: L10n.tr("help_tab_calendar_title"),
                    text: L10n.tr("help_tab_calendar_text")
                )
                helpRow(
                    title: L10n.tr("help_tab_medications_title"),
                    text: L10n.tr("help_tab_medications_text")
                )
                helpRow(
                    title: L10n.tr("help_tab_pending_title"),
                    text: L10n.tr("help_tab_pending_text")
                )
                helpRow(
                    title: L10n.tr("help_tab_settings_title"),
                    text: L10n.tr("help_tab_settings_text")
                )
            }

            Section(L10n.tr("help_section_flows")) {
                helpStep(title: L10n.tr("help_flow_create_scheduled_title"), text: L10n.tr("help_flow_create_scheduled_text"))
                helpStep(title: L10n.tr("help_flow_create_occasional_title"), text: L10n.tr("help_flow_create_occasional_text"))
                helpStep(title: L10n.tr("help_flow_mark_title"), text: L10n.tr("help_flow_mark_text"))
                helpStep(title: L10n.tr("help_flow_remove_day_title"), text: L10n.tr("help_flow_remove_day_text"))
                helpStep(title: L10n.tr("help_flow_remove_all_title"), text: L10n.tr("help_flow_remove_all_text"))
                helpStep(title: L10n.tr("help_flow_cart_title"), text: L10n.tr("help_flow_cart_text"))
                helpStep(title: L10n.tr("help_flow_aemps_search_title"), text: L10n.tr("help_flow_aemps_search_text"))
            }

            Section(L10n.tr("help_section_notes")) {
                Text(L10n.tr("help_note_time"))
                Text(L10n.tr("help_note_future"))
                Text(L10n.tr("help_note_report"))
                Text(L10n.tr("help_note_disclaimer_cart"))
            }
        }
        .textSelection(.enabled)
        .safeAreaPadding(.bottom, 84)
        .navigationTitle(L10n.tr("help_title"))
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func helpRow(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func helpStep(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
