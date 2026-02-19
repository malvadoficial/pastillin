import SwiftUI

struct TutorialView: View {
    let onSelectTab: (AppTab) -> Void
    let onFinish: () -> Void

    @State private var stepIndex: Int = 0

    private struct TutorialStep: Identifiable {
        let id: Int
        let tab: AppTab
        let title: String
        let text: String
    }

    private var steps: [TutorialStep] {
        [
            TutorialStep(
                id: 0,
                tab: .medications,
                title: L10n.tr("tutorial_page_cabinet_title"),
                text: L10n.tr("tutorial_cabinet_step_1")
            ),
            TutorialStep(
                id: 1,
                tab: .medications,
                title: L10n.tr("tutorial_page_cabinet_title"),
                text: L10n.tr("tutorial_cabinet_step_2")
            ),
            TutorialStep(
                id: 2,
                tab: .medications,
                title: L10n.tr("tutorial_page_cabinet_title"),
                text: L10n.tr("tutorial_cabinet_step_3")
            ),
            TutorialStep(
                id: 3,
                tab: .medications,
                title: L10n.tr("tutorial_page_cabinet_title"),
                text: L10n.tr("tutorial_cabinet_step_4")
            ),
            TutorialStep(
                id: 4,
                tab: .medications,
                title: L10n.tr("tutorial_page_cabinet_title"),
                text: L10n.tr("tutorial_cabinet_step_5")
            ),
            TutorialStep(
                id: 5,
                tab: .medications,
                title: L10n.tr("tutorial_page_cabinet_title"),
                text: L10n.tr("tutorial_cabinet_step_6")
            ),
            TutorialStep(
                id: 6,
                tab: .medications,
                title: L10n.tr("tutorial_page_cabinet_title"),
                text: L10n.tr("tutorial_cabinet_step_7")
            ),
            TutorialStep(
                id: 7,
                tab: .today,
                title: L10n.tr("tutorial_page_today_title"),
                text: L10n.tr("tutorial_today_step_1")
            ),
            TutorialStep(
                id: 8,
                tab: .today,
                title: L10n.tr("tutorial_page_today_title"),
                text: L10n.tr("tutorial_today_step_2")
            ),
            TutorialStep(
                id: 9,
                tab: .today,
                title: L10n.tr("tutorial_page_today_title"),
                text: L10n.tr("tutorial_today_step_3")
            ),
            TutorialStep(
                id: 10,
                tab: .today,
                title: L10n.tr("tutorial_page_today_title"),
                text: L10n.tr("tutorial_today_step_4")
            ),
            TutorialStep(
                id: 11,
                tab: .medications,
                title: L10n.tr("tutorial_page_today_title"),
                text: L10n.tr("tutorial_today_step_5")
            ),
            TutorialStep(
                id: 12,
                tab: .medications,
                title: L10n.tr("tutorial_page_today_title"),
                text: L10n.tr("tutorial_today_step_6")
            ),
            TutorialStep(
                id: 13,
                tab: .calendar,
                title: L10n.tr("tutorial_page_calendar_title"),
                text: L10n.tr("tutorial_calendar_step_1")
            ),
            TutorialStep(
                id: 14,
                tab: .calendar,
                title: L10n.tr("tutorial_page_calendar_title"),
                text: L10n.tr("tutorial_calendar_step_2")
            ),
            TutorialStep(
                id: 15,
                tab: .calendar,
                title: L10n.tr("tutorial_page_calendar_title"),
                text: L10n.tr("tutorial_calendar_step_3")
            ),
            TutorialStep(
                id: 16,
                tab: .calendar,
                title: L10n.tr("tutorial_page_calendar_title"),
                text: L10n.tr("tutorial_calendar_step_4")
            ),
            TutorialStep(
                id: 17,
                tab: .calendar,
                title: L10n.tr("tutorial_page_calendar_title"),
                text: L10n.tr("tutorial_pending_step_1")
            ),
            TutorialStep(
                id: 18,
                tab: .noTaken,
                title: L10n.tr("tutorial_page_pending_title"),
                text: L10n.tr("tutorial_pending_step_2")
            ),
            TutorialStep(
                id: 19,
                tab: .noTaken,
                title: L10n.tr("tutorial_page_pending_title"),
                text: L10n.tr("tutorial_pending_step_3")
            ),
            TutorialStep(
                id: 20,
                tab: .noTaken,
                title: L10n.tr("tutorial_page_pending_title"),
                text: L10n.tr("tutorial_pending_step_4")
            ),
            TutorialStep(
                id: 21,
                tab: .cart,
                title: L10n.tr("tutorial_page_cart_title"),
                text: L10n.tr("tutorial_cart_step_1")
            ),
            TutorialStep(
                id: 22,
                tab: .cart,
                title: L10n.tr("tutorial_page_cart_title"),
                text: L10n.tr("tutorial_cart_step_2")
            ),
            TutorialStep(
                id: 23,
                tab: .cart,
                title: L10n.tr("tutorial_page_cart_title"),
                text: L10n.tr("tutorial_cart_step_3")
            ),
            TutorialStep(
                id: 24,
                tab: .cart,
                title: L10n.tr("tutorial_page_cart_title"),
                text: L10n.tr("tutorial_cart_step_4")
            ),
            TutorialStep(
                id: 25,
                tab: .cart,
                title: L10n.tr("tutorial_page_cart_title"),
                text: L10n.tr("tutorial_cart_step_5")
            ),
            TutorialStep(
                id: 26,
                tab: .settings,
                title: L10n.tr("tutorial_page_settings_title"),
                text: L10n.tr("tutorial_settings_step_1")
            ),
            TutorialStep(
                id: 27,
                tab: .settings,
                title: L10n.tr("tutorial_page_settings_title"),
                text: L10n.tr("tutorial_settings_step_2")
            ),
            TutorialStep(
                id: 28,
                tab: .settings,
                title: L10n.tr("tutorial_page_settings_title"),
                text: L10n.tr("tutorial_settings_step_3")
            ),
            TutorialStep(
                id: 29,
                tab: .settings,
                title: L10n.tr("tutorial_page_settings_title"),
                text: L10n.tr("tutorial_settings_step_4")
            ),
            TutorialStep(
                id: 30,
                tab: .settings,
                title: L10n.tr("tutorial_page_settings_title"),
                text: L10n.tr("tutorial_settings_step_5")
            ),
            TutorialStep(
                id: 31,
                tab: .settings,
                title: L10n.tr("tutorial_page_settings_title"),
                text: L10n.tr("tutorial_settings_step_6")
            )
        ]
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                let step = steps[stepIndex]

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(L10n.tr("tutorial_title"))
                            .font(.headline.weight(.bold))
                        Spacer()
                        Button(L10n.tr("button_close")) {
                            onFinish()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppTheme.brandRed)
                    }

                    Text("\(stepIndex + 1) / \(steps.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text(step.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.brandRed)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)

                    stepTextView(step)

                    if stepIndex == steps.count - 1 {
                        Text(L10n.tr("tutorial_end_reminder"))
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(AppTheme.brandBlue)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack(spacing: 10) {
                        if stepIndex > 0 {
                            Button(L10n.tr("tutorial_prev")) {
                                withAnimation {
                                    stepIndex -= 1
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(AppTheme.brandRed)
                        }

                        Spacer()

                        if stepIndex < steps.count - 1 {
                            Button(L10n.tr("tutorial_next")) {
                                withAnimation {
                                    stepIndex += 1
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(AppTheme.brandRed)
                        } else {
                            Button(L10n.tr("tutorial_finish")) {
                                onFinish()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(AppTheme.brandRed)
                        }
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(.white.opacity(0.4), lineWidth: 1)
                )
                .padding(.horizontal, 12)
                .padding(.bottom, 98)
            }
        }
        .onAppear {
            onSelectTab(steps[stepIndex].tab)
        }
        .onChange(of: stepIndex) { _, newValue in
            onSelectTab(steps[newValue].tab)
        }
    }

    @ViewBuilder
    private func stepTextView(_ step: TutorialStep) -> some View {
        if step.id == 13 {
            highlightedCalendarLegendText()
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        } else {
            Text(step.text)
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }

    private func highlightedCalendarLegendText() -> Text {
        let isSpanish = (Locale.current.language.languageCode?.identifier.lowercased().hasPrefix("es") ?? false)
        if isSpanish {
            return Text(
                "Aquí podrás ver los días que tomaste todos los medicamentos: en \(Text("azul").bold().foregroundStyle(AppTheme.brandBlue)); los días que no tomaste alguno: en \(Text("amarillo").bold().foregroundStyle(AppTheme.brandYellow)); y los días que no tomaste ninguno: en \(Text("rojo").bold().foregroundStyle(AppTheme.brandRed)). En \(Text("rojo").bold().foregroundStyle(AppTheme.brandRed)) también aparecerán los días futuros, en los que aún no has tomado los medicamentos que te corresponden."
            )
        }

        return Text(
            "Here you can see the days when you took all medications: in \(Text("blue").bold().foregroundStyle(AppTheme.brandBlue)); days when you missed some: in \(Text("yellow").bold().foregroundStyle(AppTheme.brandYellow)); and days when you took none: in \(Text("red").bold().foregroundStyle(AppTheme.brandRed)). Future days are also shown in \(Text("red").bold().foregroundStyle(AppTheme.brandRed)) because you have not taken those doses yet."
        )
    }
}
