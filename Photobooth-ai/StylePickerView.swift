import SwiftUI

struct StylePickerView: View {
    @Environment(AppState.self) private var app

    let eventId: UUID
    let capturedImageData: Data

    @State private var selecting: PhotoStyle? = nil
    @State private var uploadError: String? = nil

    var body: some View {
        ZStack {
            BoothifyTheme.bg.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 10) {
                        Text("STEP 2 OF 3")
                            .font(.caption2.weight(.semibold))
                            .kerning(1.6)
                            .foregroundStyle(BoothifyTheme.violet)
                        GradientHeading(text: "Who do you want to be?", font: .title.bold())
                            .multilineTextAlignment(.center)
                        Text("Pick a style — we'll handle the rest")
                            .font(.subheadline)
                            .foregroundStyle(BoothifyTheme.textSecondary)
                    }
                    .padding(.top, 8)

                    LazyVGrid(
                        columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                        spacing: 10
                    ) {
                        ForEach(PhotoStyle.allCases) { style in
                            StyleTile(
                                style: style,
                                isSelecting: selecting == style,
                                isDisabled: selecting != nil && selecting != style
                            ) {
                                pick(style: style)
                            }
                        }
                    }
                    .frame(maxWidth: 620)

                    if let uploadError {
                        Text(uploadError)
                            .font(.footnote)
                            .foregroundStyle(.red.opacity(0.9))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }

                    Spacer(minLength: 20)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle("Choose style")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func pick(style: PhotoStyle) {
        guard selecting == nil else { return }
        Haptics.tap(.medium)
        selecting = style
        uploadError = nil

        Task {
            do {
                // 1. Upload source image, get photoId from backend.
                let photoId = try await BoothifyAPI.shared.uploadPhoto(
                    imageData: capturedImageData,
                    eventId: eventId,
                    style: style,
                )

                // 2. Fire AI generation. Don't await — ResultView will poll for status.
                Task.detached { [photoId, style] in
                    do {
                        _ = try await BoothifyAPI.shared.generatePhoto(photoId: photoId, style: style)
                    } catch {
                        // Generation errors surface through the polling response (status=failed).
                        // No need to handle here.
                    }
                }

                // 3. Navigate to result; ResultView takes over polling.
                app.push(.result(eventId: eventId, photoId: photoId))
            } catch {
                Haptics.notify(.error)
                uploadError = (error as? APIError)?.errorDescription ?? error.localizedDescription
                selecting = nil
            }
        }
    }
}

private struct StyleTile: View {
    let style: PhotoStyle
    let isSelecting: Bool
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                // Real AI sample photo as backdrop
                Image(style.previewAsset)
                    .resizable()
                    .scaledToFill()

                // Bottom gradient for legible caption
                LinearGradient(
                    colors: [.clear, .black.opacity(0.4), .black.opacity(0.85)],
                    startPoint: .top, endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(style.label)
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.5), radius: 6, y: 1)
                    Text(style.descriptionText)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                }
                .padding(14)

                if isSelecting {
                    ZStack {
                        Rectangle().fill(.ultraThinMaterial)
                        VStack(spacing: 12) {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.white)
                                .scaleEffect(1.4)
                            Text("Generating…")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                        }
                    }
                    .transition(.opacity)
                    .accessibilityLabel("Generating \(style.label)")
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )
            .opacity(isDisabled ? 0.35 : 1)
            .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled || isSelecting)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(style.label) style. \(style.descriptionText)")
    }
}

#Preview {
    NavigationStack {
        StylePickerView(
            eventId: UUID(),
            capturedImageData: Data()
        )
    }
    .environment(AppState())
}
