import SwiftUI

struct TutorialSlide: Codable, Identifiable {
    let id: String
    let imageName: String
    let textKey: String
}

struct TutorialView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var currentIndex = 0

    private let slides: [TutorialSlide] = TutorialSlidesLoader.load()

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                VStack(spacing: 0) {
                    topBar
                        .padding(.horizontal, 16)
                        .padding(.top, 8)

                    Spacer(minLength: 8)

                    if let slide = currentSlide {
                        Image(slide.imageName)
                            .resizable()
                            .scaledToFit()
                            .frame(
                                maxWidth: min(proxy.size.width - 12, 900),
                                maxHeight: proxy.size.height * 0.7
                            )
                    }

                    ScrollView(.vertical, showsIndicators: true) {
                        Text(currentSlide.map { L10n.tr($0.textKey) } ?? "")
                            .font(.body)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: min(proxy.size.width - 24, 900), alignment: .leading)
                            .padding(.vertical, 12)
                    }
                    .frame(maxWidth: min(proxy.size.width - 24, 900), maxHeight: 130)
                    .padding(.top, 10)

                    Spacer(minLength: 8)

                    HStack {
                        Button {
                            move(-1)
                        } label: {
                            Label(L10n.tr("tutorial_prev"), systemImage: "chevron.left")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!canMoveBack)

                        Spacer()

                        Text("\(displayIndex)/\(max(slides.count, 1))")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Button {
                            if isLastSlide {
                                dismiss()
                            } else {
                                move(1)
                            }
                        } label: {
                            Label(
                                isLastSlide ? L10n.tr("tutorial_finish") : L10n.tr("tutorial_next"),
                                systemImage: "chevron.right"
                            )
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(slides.isEmpty)
                    }
                    .frame(maxWidth: min(proxy.size.width - 32, 700))
                    .padding(.bottom, 18)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(uiColor: .systemBackground))
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .interactiveDismissDisabled()
    }

    private var topBar: some View {
        HStack {
            Spacer()
            Button(L10n.tr("tutorial_skip")) {
                dismiss()
            }
            .font(.headline)
        }
    }

    private var currentSlide: TutorialSlide? {
        guard slides.indices.contains(currentIndex) else { return nil }
        return slides[currentIndex]
    }

    private var canMoveBack: Bool {
        currentIndex > 0
    }

    private var isLastSlide: Bool {
        currentIndex >= slides.count - 1
    }

    private var displayIndex: Int {
        guard !slides.isEmpty else { return 0 }
        return currentIndex + 1
    }

    private func move(_ offset: Int) {
        let next = currentIndex + offset
        guard slides.indices.contains(next) else { return }
        currentIndex = next
    }
}

enum TutorialSlidesLoader {
    static func load() -> [TutorialSlide] {
        guard
            let url = Bundle.main.url(forResource: "tutorial_slides", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let slides = try? JSONDecoder().decode([TutorialSlide].self, from: data),
            !slides.isEmpty
        else {
            return fallbackSlides
        }

        return slides
    }

    static let fallbackSlides: [TutorialSlide] = [
        TutorialSlide(id: "cabinet", imageName: "EmptyMedicinesState", textKey: "tutorial_cabinet_step_1"),
        TutorialSlide(id: "calendar", imageName: "SplashPortrait", textKey: "tutorial_calendar_step_1"),
        TutorialSlide(id: "today", imageName: "SplashLandscape", textKey: "tutorial_today_step_1"),
        TutorialSlide(id: "cart", imageName: "ShoppingCartEmptyState", textKey: "tutorial_cart_step_1"),
        TutorialSlide(id: "settings", imageName: "PendingEmptyState", textKey: "tutorial_settings_step_1")
    ]
}
