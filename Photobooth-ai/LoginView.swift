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

    var body: some View {
        ZStack {
            BoothifyTheme.bg.ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer()

                VStack(spacing: 12) {
                    Image(systemName: "camera.aperture")
                        .font(.system(size: 56, weight: .semibold))
                        .foregroundStyle(BoothifyTheme.violet)
                        .accessibilityHidden(true)

                    Text("Boothify")
                        .font(BoothifyType.displayMedium)
                        .foregroundStyle(.white)

                    Text("Run AI photobooth & 360 events for your guests.")
                        .font(.subheadline)
                        .foregroundStyle(BoothifyTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                Spacer()

                VStack(spacing: 12) {
                    SignInWithAppleButton(
                        .signIn,
                        onRequest: { request in
                            let nonce = AuthClient.randomNonceString()
                            rawNonce = nonce
                            // Request both — Apple only delivers them on the
                            // VERY FIRST sign-in for this Apple ID + app pair.
                            // Persist locally on receipt so they survive future
                            // logins (which only return the user identifier).
                            request.requestedScopes = [.email, .fullName]
                            request.nonce = AuthClient.sha256(nonce)
                        },
                        onCompletion: handle(result:),
                    )
                    .signInWithAppleButtonStyle(.white)
                    .frame(height: 54)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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
                            .foregroundStyle(.red.opacity(0.9))
                            .multilineTextAlignment(.center)
                    }

                    Text("Your Apple ID is used only to sign you in. We never see your password.")
                        .font(.caption2)
                        .foregroundStyle(BoothifyTheme.textTertiary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 8)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
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

            let nonce = rawNonce
            isSigningIn = true
            Task {
                do {
                    let session = try await AuthClient.shared.signInWithApple(
                        identityToken: identityToken,
                        nonce: nonce,
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
