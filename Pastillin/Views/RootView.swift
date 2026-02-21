//
//  RootView.swift
//  MediRecord
//
//  Created by José Manuel Rives on 11/2/26.
//

import SwiftUI
import SwiftData
import UIKit

extension Notification.Name {
    static let calendarJumpToToday = Notification.Name("calendarJumpToToday")
    static let intakeLogsDidChange = Notification.Name("intakeLogsDidChange")
}

enum AppTab: String {
    case today
    case calendar
    case medications
    case cart
    case noTaken
    case settings
}

struct RootView: View {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("selectedTab") private var selectedTab: AppTab = .medications
    @AppStorage("legalDisclaimerAccepted") private var legalDisclaimerAccepted = false
    @AppStorage("hasSeenOnboardingTutorial") private var hasSeenOnboardingTutorial = false
    @Query private var settings: [AppSettings]
    @Query private var medications: [Medication]
    @Query private var logs: [IntakeLog]
    @Query private var intakes: [Intake]
    @State private var showTutorial = false
    
    init() {
        UITabBar.appearance().isHidden = true
    }

    var body: some View {
        Group {
            if selectedTab == .noTaken {
                NoTakenView()
            } else {
                TabView(selection: tabSelectionBinding) {
                    TodayView()
                        .tabItem { Label(L10n.tr("tab_today"), systemImage: "checklist") }
                        .tag(AppTab.today)

                    CalendarView()
                        .tabItem { Label(L10n.tr("tab_calendar"), systemImage: "calendar") }
                        .tag(AppTab.calendar)

                    MedicationsView()
                        .tabItem { Label(L10n.tr("tab_medications"), systemImage: "pills") }
                        .tag(AppTab.medications)

                    ShoppingCartView()
                        .tabItem { Label(L10n.tr("cart_title"), systemImage: "cart") }
                        .tag(AppTab.cart)

                    SettingsView()
                        .tabItem { Label(L10n.tr("tab_settings"), systemImage: "gearshape") }
                        .tag(AppTab.settings)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            customBottomBar
        }
        .preferredColorScheme(preferredColorScheme)
        .onAppear {
            evaluateInitialTutorialPresentation()
        }
        .onChange(of: legalDisclaimerAccepted) { _, _ in
            evaluateInitialTutorialPresentation()
        }
        .onChange(of: medications.count) { _, _ in
            evaluateInitialTutorialPresentation()
        }
        .onChange(of: logs.count) { _, _ in
            evaluateInitialTutorialPresentation()
        }
        .onChange(of: intakes.count) { _, _ in
            evaluateInitialTutorialPresentation()
        }
        .fullScreenCover(isPresented: $showTutorial, onDismiss: {
            hasSeenOnboardingTutorial = true
        }) {
            TutorialView()
        }
    }


    private var preferredColorScheme: ColorScheme? {
        let mode = settings.first?.uiAppearanceMode ?? .system
        switch mode {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    private var tabSelectionBinding: Binding<AppTab> {
        Binding(
            get: { selectedTab },
            set: { newValue in
                selectedTab = newValue
                if newValue == .calendar {
                    NotificationCenter.default.post(name: .calendarJumpToToday, object: nil)
                }
            }
        )
    }

    private var customBottomBar: some View {
        HStack(spacing: 4) {
            bottomBarButton(.today, title: L10n.tr("tab_today"), systemImage: "checklist")
            bottomBarButton(.calendar, title: L10n.tr("tab_calendar"), systemImage: "calendar")
            bottomBarButton(.medications, title: L10n.tr("tab_medications"), systemImage: "pills")
            bottomBarButton(.settings, title: L10n.tr("tab_settings"), systemImage: "gearshape")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(.white.opacity(0.35), lineWidth: 0.8)
                }
                .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
        }
        .padding(.horizontal, 8)
        .padding(.top, 6)
        .padding(.bottom, 4)
    }

    private func bottomBarButton(_ tab: AppTab, title: String, systemImage: String) -> some View {
        let isSelected = selectedTab == tab
        let tabColor = color(for: tab)

        return Button {
            tabSelectionBinding.wrappedValue = tab
        } label: {
            VStack(spacing: 3) {
                Image(systemName: systemImage)
                    .font(.system(size: isSelected ? 20 : 18, weight: .semibold))
                Text(title)
                    .font(.caption2.weight(isSelected ? .bold : .regular))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(tabColor)
            .opacity(isSelected ? 1 : 0.55)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .background {
                if isSelected {
                    Capsule(style: .continuous)
                        .fill(tabColor.opacity(0.22))
                        .overlay {
                            Capsule(style: .continuous)
                                .stroke(tabColor.opacity(0.75), lineWidth: 1.1)
                        }
                }
            }
            .scaleEffect(isSelected ? 1.04 : 1.0)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func color(for tab: AppTab) -> Color {
        switch tab {
        case .today:
            return AppTheme.brandBlue
        case .calendar:
            return AppTheme.brandRed
        case .medications:
            return AppTheme.brandYellow
        case .cart:
            return AppTheme.brandYellow
        case .noTaken:
            return AppTheme.brandRed
        case .settings:
            return colorScheme == .dark ? .white : .black
        }
    }

    private var shouldAutoPresentTutorial: Bool {
        legalDisclaimerAccepted &&
        !hasSeenOnboardingTutorial &&
        medications.isEmpty &&
        logs.isEmpty &&
        intakes.isEmpty
    }

    private func evaluateInitialTutorialPresentation() {
        guard shouldAutoPresentTutorial else { return }
        showTutorial = true
    }
}
