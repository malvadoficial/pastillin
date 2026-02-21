//
//  PastillinApp.swift
//  Pastillin
//
//  Created by José Manuel Rives on 11/2/26.
//
import SwiftUI
import SwiftData
import UserNotifications
import UIKit

@main
struct PastillinApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Medication.self,
            IntakeLog.self,
            Intake.self,
            AppSettings.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        return try! ModelContainer(for: schema, configurations: [config])
    }()

    var body: some Scene {
        WindowGroup {
            SplashGateView()
                .tint(AppTheme.brandBlue)
                .environment(\.font, appBaseFont)
        }
        .modelContainer(sharedModelContainer)
    }

    private var appBaseFont: Font {
        if UIFont(name: "Manrope", size: 17) != nil {
            return .custom("Manrope", size: 17, relativeTo: .body)
        }
        if UIFont(name: "Manrope-Regular", size: 17) != nil {
            return .custom("Manrope-Regular", size: 17, relativeTo: .body)
        }
        return .body
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil
    ) -> Bool {
        FontRegistrar.registerAppFonts()
        UNUserNotificationCenter.current().delegate = self
        NotificationService.registerCategories()
        UserDefaults.standard.set(AppTab.medications.rawValue, forKey: "selectedTab")
        return true
    }

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        .allButUpsideDown
    }

    // Para que la notificación se muestre también con la app abierta
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // Si llega la notificación con la app abierta, también llevar a "Hoy"
        UserDefaults.standard.set(AppTab.today.rawValue, forKey: "selectedTab")
        return [.banner, .sound]
    }


func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse
) async {
    let action = response.actionIdentifier

    if action == NotificationService.snoozeOneHourAction {
        try? await NotificationService.scheduleSnoozeOneHourReminder()
        return
    }

    if action == NotificationService.openAction || action == UNNotificationDefaultActionIdentifier {
        // Lleva la app a la pestaña "Hoy" al abrir la notificación
        UserDefaults.standard.set(AppTab.today.rawValue, forKey: "selectedTab")
    }
}

}
