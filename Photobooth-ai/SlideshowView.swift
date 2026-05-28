import SwiftUI

struct SlideshowView: View {
    @Environment(AppState.self) private var app
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
    }

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
        .animation(.easeInOut(duration: 0.6), value: currentIndex)
    }

    private func photoSlide(_ photo: Photo) -> some View {
        ZStack {
            if let url = photo.generatedURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ProgressView().tint(.white)
                    case .success(let img):
                        img.resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: .infinity)
                    case .failure:
                        photo.style.accentGradient.frame(maxWidth: .infinity, maxHeight: .infinity)
                    @unknown default:
                        photo.style.accentGradient.frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            } else {
                photo.style.accentGradient.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .accessibilityLabel("Slide: \(photo.style.label) photo")
    }

    private var overlayControls: some View {
        VStack {
            HStack {
                Button {
                    Haptics.tap()
                    timerTask?.cancel()
                    refreshTask?.cancel()
                    app.pop()
                } label: {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(.black.opacity(0.45))
                        .clipShape(Circle())
                        .overlay(Circle().stroke(.white.opacity(0.15), lineWidth: 1))
                }
                .accessibilityLabel("Close slideshow")
                Spacer()
                Text("\((currentIndex % max(photos.count, 1)) + 1) / \(photos.count)")
                    // QW6 — monospacedDigit so the counter doesn't jiggle
                    // as the index ticks; plus a VoiceOver label so
                    // screen-reader users hear position context.
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.45))
                    .clipShape(Capsule())
                    .accessibilityLabel("Slide \((currentIndex % max(photos.count, 1)) + 1) of \(photos.count)")
            }
            .padding(20)
            Spacer()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "tv")
                .font(.system(size: 48, weight: .bold))
                .foregroundStyle(BoothifyTheme.violet)
                .accessibilityHidden(true)
            Text("Slideshow is empty")
                .font(.headline)
                .foregroundStyle(.white)
            Text("Take photos via the kiosk — they appear here automatically.")
                .font(.footnote)
                .foregroundStyle(BoothifyTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button("Back") {
                Haptics.tap()
                app.pop()
            }
            .buttonStyle(SecondaryButtonStyle())
            .frame(maxWidth: 200)
            .padding(.top, 8)
        }
    }

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
