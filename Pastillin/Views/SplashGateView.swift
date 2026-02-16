import SwiftUI

struct SplashGateView: View {
    private let splashDuration: UInt64 = 2_200_000_000

    @AppStorage("legalDisclaimerAccepted") private var legalDisclaimerAccepted = false
    @State private var showSplash = true
    @State private var showLegalDisclaimer = false

    var body: some View {
        ZStack {
            RootView()

            if showSplash {
                LaunchSplashView()
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .task {
            guard showSplash else { return }
            try? await Task.sleep(nanoseconds: splashDuration)
            withAnimation(.easeOut(duration: 0.25)) {
                showSplash = false
            }
            if !legalDisclaimerAccepted {
                showLegalDisclaimer = true
            }
        }
        .fullScreenCover(isPresented: $showLegalDisclaimer) {
            LegalDisclaimerView(isMandatory: true) {
                legalDisclaimerAccepted = true
                showLegalDisclaimer = false
            }
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
