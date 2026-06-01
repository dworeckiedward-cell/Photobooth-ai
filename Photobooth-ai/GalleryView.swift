import SwiftUI

struct GalleryView: View {
    @Environment(AppState.self) private var app
    let eventId: UUID

    @State private var photos: [Photo] = []
    @State private var isLoading: Bool = true
    @State private var errorMessage: String?

    private var event: Event? { app.event(id: eventId) }

    var body: some View {
        ZStack {
            BoothifyTheme.bg.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    Text("\(photos.count) \(photos.count == 1 ? "photo" : "photos")")
                        .font(.footnote)
                        .foregroundStyle(BoothifyTheme.textTertiary)
                        .padding(.top, 8)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(BoothifyTheme.error)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }

                    if isLoading && photos.isEmpty {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(BoothifyTheme.violet)
                            .padding(.top, 80)
                    } else if photos.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "photo.stack")
                                .font(.system(size: 56, weight: .bold))
                                .foregroundStyle(BoothifyTheme.textMuted)
                                .accessibilityHidden(true)
                            Text("No photos yet")
                                .font(.body)
                                .foregroundStyle(BoothifyTheme.textSecondary)
                            Text("Take photos via the kiosk and they'll appear here.")
                                .font(.footnote)
                                .foregroundStyle(BoothifyTheme.textTertiary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)

                            Button {
                                Haptics.tap(.medium)
                                app.push(.camera(eventId: eventId))
                            } label: {
                                Text("Start capturing")
                                    .font(.callout.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 44)
                                    .background(BoothifyTheme.violet)
                                    .clipShape(.capsule)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Start capturing photos")
                            .padding(.top, 8)
                        }
                        .padding(.top, 60)
                    } else {
                        LazyVGrid(
                            columns: [
                                GridItem(.flexible(), spacing: 4),
                                GridItem(.flexible(), spacing: 4),
                                GridItem(.flexible(), spacing: 4),
                            ],
                            spacing: 4
                        ) {
                            ForEach(photos) { photo in
                                Button {
                                    Haptics.tap()
                                    app.push(.result(eventId: eventId, photoId: photo.id))
                                } label: {
                                    GalleryThumbnail(photo: photo)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("\(photo.style.label) photo")
                            }
                        }
                    }
                }
                .padding(.bottom, 40)
            }
            .refreshable {
                await loadPhotos()
            }
        }
        .navigationTitle(event?.name ?? "Gallery")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: eventId) {
            await loadPhotos()
        }
    }

    private func loadPhotos() async {
        guard let slug = event?.slug else {
            errorMessage = "Event not loaded"
            isLoading = false
            return
        }
        isLoading = true
        errorMessage = nil
        do {
            let list = try await BoothifyAPI.shared.listEventPhotos(slug: slug, status: .completed, limit: 200)
            photos = list.photos
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
        isLoading = false
    }
}

private struct GalleryThumbnail: View {
    let photo: Photo

    var body: some View {
        ZStack {
            if let url = photo.generatedURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        Rectangle().fill(BoothifyTheme.surface1)
                    case .success(let img):
                        img.resizable().scaledToFill()
                    case .failure:
                        Image(photo.style.previewAsset).resizable().scaledToFill()
                    @unknown default:
                        Rectangle().fill(BoothifyTheme.surface1)
                    }
                }
            } else {
                Image(photo.style.previewAsset)
                    .resizable()
                    .scaledToFill()
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipped()
    }
}

#Preview {
    NavigationStack {
        GalleryView(eventId: UUID())
    }
    .environment(AppState())
}
