import SwiftUI

struct SlideshowView: View {
    @Environment(AppState.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let eventId: UUID

    @State private var currentIndex: Int = 0
    @State private var photos: [Photo] = []
    @State private var isLoading: Bool = true
    @State private var timerTask: Task<Void, Never>? = nil
    @State private var refreshTask: Task<Void, Never>? = nil

    private var event: Event? { app.event(id: eventId) }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if isLoading && photos.isEmpty {
                ProgressView().tint(.white)
            } else if photos.isEmpty {
                emptyState
            } else {
                slidesStack
                overlayControls
            }
        }
        .task(id: eventId) {
            await loadPhotos()
            startTimer()
            startBackgroundRefresh()
        }
        .onDisappear {
            timerTask?.cancel()
            refreshTask?.cancel()
        }
        .ignoresSafeArea()
    }

    // MARK: - Slides

    private var slidesStack: some View {
        ZStack {
            ForEach(photos.indices, id: \.self) { idx in
                if idx == currentIndex % max(photos.count, 1) {
                    photoSlide(photos[idx])
                        .transition(.opacity)
                        .id(idx)
                }
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.6), value: currentIndex)
    }

    private func photoSlide(_ photo: Photo) -> some View {
        ZStack {
            if let url = photo.generatedURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        Color.black
                            .overlay(ProgressView().tint(.white))
                    case .success(let img):
                        img
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .clipped()
                    case .failure:
                        photo.style.accentGradient
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    @unknown default:
                        photo.style.accentGradient
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            } else {
                photo.style.accentGradient
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .accessibilityLabel("Slide: \(photo.style.label) photo")
    }

    // MARK: - Overlay controls

    private var overlayControls: some View {
        VStack(spacing: 0) {
            // Top bar: close + counter
            HStack {
                closeButton
                Spacer()
                slideCounter
            }
            .padding(.horizontal, BoothifySpacing.md)
            .padding(.top, BoothifySpacing.md)
            .background(
                LinearGradient(
                    colors: [.black.opacity(0.55), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea(edges: .top)
            )

            Spacer()

            // Bottom progress dots
            progressDots
                .padding(.bottom, BoothifySpacing.lg)
                .background(
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.45)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
    }

    private var closeButton: some View {
        Button {
            Haptics.tap()
            timerTask?.cancel()
            refreshTask?.cancel()
            app.pop()
        } label: {
            Image(systemName: "xmark")
                .font(.body.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(.black.opacity(0.40))
                .clipShape(Circle())
                .overlay(
                    Circle().stroke(.white.opacity(0.12), lineWidth: 1)
                )
        }
        .accessibilityLabel("Close slideshow")
    }

    private var slideCounter: some View {
        Text("\((currentIndex % max(photos.count, 1)) + 1) / \(photos.count)")
            .font(.caption.weight(.semibold).monospacedDigit())
            .foregroundStyle(.white.opacity(0.85))
            .padding(.horizontal, BoothifySpacing.sm + 4)
            .padding(.vertical, BoothifySpacing.xs + 2)
            .background(.black.opacity(0.40))
            .clipShape(Capsule())
            .accessibilityLabel("Slide \((currentIndex % max(photos.count, 1)) + 1) of \(photos.count)")
    }

    private var progressDots: some View {
        HStack(spacing: 6) {
            ForEach(photos.indices, id: \.self) { idx in
                let isCurrent = idx == currentIndex % max(photos.count, 1)
                Capsule()
                    .fill(isCurrent ? Color.white : Color.white.opacity(0.30))
                    .frame(width: isCurrent ? 20 : 6, height: 4)
                    .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.85), value: currentIndex)
            }
        }
        .padding(.horizontal, BoothifySpacing.lg)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: BoothifySpacing.md) {
            Image(systemName: "tv")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(BoothifyTheme.violet)
                .accessibilityHidden(true)

            VStack(spacing: BoothifySpacing.xs) {
                Text("Slideshow is empty")
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                Text("Take photos via the kiosk — they appear here automatically.")
                    .font(.footnote)
                    .foregroundStyle(BoothifyTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, BoothifySpacing.xl)
            }

            Button("Back") {
                Haptics.tap()
                app.pop()
            }
            .buttonStyle(SecondaryButtonStyle())
            .frame(maxWidth: 200)
            .padding(.top, BoothifySpacing.xs)
        }
    }

    // MARK: - Data

    private func loadPhotos() async {
        guard let slug = event?.slug else {
            isLoading = false
            return
        }
        do {
            let list = try await BoothifyAPI.shared.listEventPhotos(slug: slug, status: .completed, limit: 200)
            photos = list.photos
        } catch {
            // Silent — slideshow shouldn't surface errors to guests.
        }
        isLoading = false
    }

    private func startTimer() {
        timerTask?.cancel()
        timerTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                if !Task.isCancelled {
                    currentIndex &+= 1
                }
            }
        }
    }

    /// Re-fetches photos every 20s so new guest captures show up live during the event.
    private func startBackgroundRefresh() {
        refreshTask?.cancel()
        refreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                if !Task.isCancelled {
                    await loadPhotos()
                }
            }
        }
    }
}

#Preview {
    SlideshowView(eventId: UUID())
        .environment(AppState())
}
