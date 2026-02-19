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
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("selectedTab") private var selectedTab: AppTab = .today
    @AppStorage("hasSeenOnboardingTutorial") private var hasSeenOnboardingTutorial = false
    @AppStorage("showOnboardingTutorialNow") private var showOnboardingTutorialNow = false
    @AppStorage("tutorialDemoDataCreated") private var tutorialDemoDataCreated = false
    @AppStorage("tutorialDemoMedicationIDs") private var tutorialDemoMedicationIDsRaw = ""
    @AppStorage("tutorialDemoCleanupNow") private var tutorialDemoCleanupNow = false
    @Query private var settings: [AppSettings]
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
            if !hasSeenOnboardingTutorial {
                prepareTutorialDemoDataIfNeeded()
                showTutorial = true
            }
        }
        .onChange(of: showOnboardingTutorialNow) { _, newValue in
            guard newValue else { return }
            prepareTutorialDemoDataIfNeeded()
            showTutorial = true
        }
        .overlay {
            if showTutorial {
                TutorialView(
                    onSelectTab: { tab in
                        tabSelectionBinding.wrappedValue = tab
                    },
                    onFinish: {
                        hasSeenOnboardingTutorial = true
                        showOnboardingTutorialNow = false
                        showTutorial = false
                        selectedTab = .today
                        // Solicita limpieza inmediata en SplashGate (desmonta UI antes de borrar).
                        if tutorialDemoDataCreated {
                            tutorialDemoCleanupNow = true
                        }
                    }
                )
                .zIndex(10)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showTutorial)
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

    private func prepareTutorialDemoDataIfNeeded() {
        guard !hasSeenOnboardingTutorial else { return }
        guard !tutorialDemoDataCreated else { return }

        let meds = (try? modelContext.fetch(FetchDescriptor<Medication>())) ?? []
        let logs = (try? modelContext.fetch(FetchDescriptor<IntakeLog>())) ?? []
        guard meds.isEmpty && logs.isEmpty else { return }

        if let ids = try? TutorialDemoDataService.seed(modelContext: modelContext) {
            tutorialDemoMedicationIDsRaw = ids.map(\.uuidString).joined(separator: ",")
            tutorialDemoDataCreated = true
        }
    }

}
