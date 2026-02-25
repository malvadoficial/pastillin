import SwiftUI
import SwiftData

struct SplashGateView: View {
    @Environment(\.modelContext) private var modelContext
    private let splashDuration: UInt64 = 2_200_000_000

    @AppStorage("legalDisclaimerAccepted") private var legalDisclaimerAccepted = false
    @AppStorage("hasSeenOnboardingTutorial") private var hasSeenOnboardingTutorial = false
    @AppStorage("deleteAllDataNow") private var deleteAllDataNow = false
    @AppStorage("deleteAllDataCompleted") private var deleteAllDataCompleted = false
    @State private var showSplash = true
    @State private var showLegalDisclaimer = false
    @State private var isCleaningData = false

    var body: some View {
        ZStack {
            if !isCleaningData {
                RootView()
            } else {
                Color.black.ignoresSafeArea()
            }

            if showSplash {
                LaunchSplashView()
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .task {
            guard showSplash else { return }
            runDeleteAllDataIfNeeded()
            try? IntakeSchedulingService.bootstrapScheduledIntakes(modelContext: modelContext)
            try? await Task.sleep(nanoseconds: splashDuration)
            withAnimation(.easeOut(duration: 0.25)) {
                showSplash = false
            }
            if !legalDisclaimerAccepted {
                showLegalDisclaimer = true
            }
        }
        .onChange(of: deleteAllDataNow) { _, newValue in
            guard newValue else { return }
            runDeleteAllDataIfNeeded()
        }
        .fullScreenCover(isPresented: $showLegalDisclaimer) {
            LegalDisclaimerView(isMandatory: true) {
                legalDisclaimerAccepted = true
                showLegalDisclaimer = false
            }
        }
    }

    private func runDeleteAllDataIfNeeded() {
        guard deleteAllDataNow else { return }
        isCleaningData = true

        // Deja que SwiftUI desmonte RootView antes de tocar el contexto.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            try? BackupService.clearAllData(modelContext: modelContext)

            hasSeenOnboardingTutorial = false
            deleteAllDataNow = false
            deleteAllDataCompleted = true
            isCleaningData = false
        }
    }
}

private struct LaunchSplashView: View {
    var body: some View {
        GeometryReader { proxy in
            let isLandscape = proxy.size.width > proxy.size.height

            ZStack {
                Color.black
                    .ignoresSafeArea()

                Image(isLandscape ? "SplashLandscape" : "SplashPortrait")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .clipped()
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea()
    }
}
