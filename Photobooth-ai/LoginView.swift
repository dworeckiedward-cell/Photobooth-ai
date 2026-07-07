import SwiftUI
import AuthenticationServices

/// Sign-in gate. Shown by RootView when AppState has no session. Sign in with
/// Apple → backend exchanges the identityToken for a Supabase session →
/// AppState persists tokens to Keychain → RootView swaps in the main app.
struct LoginView: View {
    @Environment(AppState.self) private var app
    @Environment(\.colorScheme) private var colorScheme

    @State private var rawNonce: String = ""
    @State private var isSigningIn: Bool = false
    @State private var errorMessage: String?

    @ScaledMetric(relativeTo: .largeTitle) private var wordmarkSize: CGFloat = 46
    @ScaledMetric(relativeTo: .title)      private var iconSize: CGFloat = 38

    var body: some View {
        ZStack {
            AtmosphericBackground()

            // Ambient violet bloom at top-center
            RadialGradient(
                colors: [BoothifyTheme.violet.opacity(0.18), .clear],
                center: .init(x: 0.5, y: -0.05),
                startRadius: 0,
                endRadius: 380
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // ── Brand hero ────────────────────────────────
                VStack(spacing: BoothifySpacing.xl) {
                    // Icon card with layered glow
                    ZStack {
                        // Outer diffuse glow
                        Circle()
                            .fill(BoothifyTheme.violet.opacity(0.14))
                            .frame(width: 200, height: 200)
                            .blur(radius: 48)

                        // Card
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .environment(\.colorScheme, .dark)
                            .frame(width: 92, height: 92)
                            .overlay(
                                RoundedRectangle(cornerRadius: 28, style: .continuous)
                                    .stroke(
                                        LinearGradient(
                                            colors: [
                                                BoothifyTheme.violet.opacity(0.65),
                                                BoothifyTheme.violet.opacity(0.18)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1.5
                                    )
                            )
                            .shadow(color: BoothifyTheme.violet.opacity(0.28), radius: 28, y: 14)

                        Image(systemName: "wand.and.stars")
                            .font(.system(size: iconSize, weight: .semibold))
                            .foregroundStyle(BoothifyTheme.violet)
                            .symbolEffect(.variableColor.iterative.reversing, options: .repeating)
                    }
                    .accessibilityHidden(true)

                    // Wordmark + tagline
                    VStack(spacing: BoothifySpacing.sm) {
                        Text("Boothify")
                            .font(.system(size: wordmarkSize, weight: .bold, design: .default))
                            .tracking(-1.2)
                            .foregroundStyle(.white)

                        Text("AI photo booth for your events")
                            .font(.callout)
                            .foregroundStyle(BoothifyTheme.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, BoothifySpacing.xl)

                Spacer()
                Spacer()

                // ── Sign-in section ───────────────────────────
                VStack(spacing: BoothifySpacing.md) {
                    SignInWithAppleButton(
                        .signIn,
                        onRequest: { request in
                            let nonce = AuthClient.randomNonceString()
                            rawNonce = nonce
                            // Request both — Apple only delivers them on the
                            // VERY FIRST sign-in for this Apple ID + app pair.
                            request.requestedScopes = [.email, .fullName]
                            request.nonce = AuthClient.sha256(nonce)
                        },
                        onCompletion: handle(result:)
                    )
                    .signInWithAppleButtonStyle(.white)
                    .frame(height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: BoothifyRadius.tile, style: .continuous))
                    .disabled(isSigningIn)
                    .opacity(isSigningIn ? 0.6 : 1)

                    if isSigningIn {
                        HStack(spacing: 8) {
                            ProgressView().tint(BoothifyTheme.textSecondary)
                            Text("Signing in…")
                                .font(.footnote)
                                .foregroundStyle(BoothifyTheme.textSecondary)
                        }
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(BoothifyTheme.error)
                            .multilineTextAlignment(.center)
                    }

                    Text("Your Apple ID is used only to sign you in.\nWe never see your password.")
                        .font(.caption2)
                        .foregroundStyle(BoothifyTheme.textMuted)
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                }
                .padding(.horizontal, BoothifySpacing.lg)
                .padding(.bottom, 48)
            }
        }
    }

    private func handle(result: Result<ASAuthorization, Error>) {
        errorMessage = nil

        switch result {
        case .failure(let err as ASAuthorizationError) where err.code == .canceled:
            return
        case .failure(let err):
            errorMessage = err.localizedDescription
            return
        case .success(let auth):
            guard
                let credential = auth.credential as? ASAuthorizationAppleIDCredential,
                let tokenData = credential.identityToken,
                let identityToken = String(data: tokenData, encoding: .utf8)
            else {
                errorMessage = "Apple did not return an identity token."
                return
            }

            // First-login persistence: Apple only ships email + fullName THE
            // FIRST TIME a user authorizes this app. Capture them now so the
            // backend can store them and we never lose them. Subsequent logins
            // return nil for both and just identify by `credential.user`.
            let firstLoginEmail = credential.email
            let firstLoginFullName = credential.fullName.map(Self.formatFullName(_:))
            if let firstLoginEmail {
                AppleProfileCache.persistFirstLogin(
                    userId: credential.user,
                    email: firstLoginEmail,
                    fullName: firstLoginFullName
                )
            }

            // One-time authorization code — the backend exchanges it for an Apple
            // refresh token it can revoke on account deletion (guideline 5.1.1(v)).
            let authorizationCode = credential.authorizationCode
                .flatMap { String(data: $0, encoding: .utf8) }

            let nonce = rawNonce
            isSigningIn = true
            Task {
                do {
                    let session = try await AuthClient.shared.signInWithApple(
                        identityToken: identityToken,
                        nonce: nonce,
                        authorizationCode: authorizationCode,
                        firstLoginEmail: firstLoginEmail,
                        firstLoginFullName: firstLoginFullName,
                    )
                    app.setSession(session)
                } catch {
                    errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
                }
                isSigningIn = false
            }
        }
    }

    private static func formatFullName(_ components: PersonNameComponents) -> String {
        let f = PersonNameComponentsFormatter()
        f.style = .default
        return f.string(from: components)
    }

}

#Preview {
    LoginView()
        .environment(AppState())
}
