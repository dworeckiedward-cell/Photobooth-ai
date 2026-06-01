import SwiftUI
import UIKit

/// M5: 3-field connect wizard for Twilio. Two flows side-by-side:
///
/// - **API Key (recommended)**: operator pastes Account SID (`AC...`),
///   API Key SID (`SK...`), API Key Secret. Scoped + revocable.
/// - **Account Token (legacy)**: Account SID + Auth Token. Works but the
///   Auth Token has god-mode on the entire Twilio account.
///
/// Either way, credentials land in Keychain via `KeychainStore`. "Send test
/// SMS" rounds-trips to a number the operator provides so they confirm the
/// pipeline works before going live.
struct TwilioOnboardingSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var kind: TwilioCredentials.CredentialKind = .apiKey
    @State private var accountSid: String = ""
    @State private var authSid: String = ""     // == accountSid when kind == .accountToken
    @State private var authSecret: String = ""
    @State private var fromNumber: String = ""

    @State private var testNumber: String = ""
    @State private var sending: Bool = false
    @State private var resultMessage: String? = nil
    @State private var resultIsError: Bool = false
    @State private var confirmDisconnect: Bool = false

    private var canSave: Bool {
        let sid = kind == .accountToken ? accountSid : authSid
        return !accountSid.isEmpty && !sid.isEmpty && !authSecret.isEmpty && !fromNumber.isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                BoothifyTheme.bg.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: BoothifySpacing.md) {
                        // Credential type picker
                        credentialTypeCard

                        // Credentials
                        credentialsCard

                        // Save + email
                        actionsCard

                        // Test SMS
                        testCard

                        // Disconnect
                        if KeychainStore.loadTwilioCredentials() != nil {
                            disconnectCard
                        }
                    }
                    .padding(.horizontal, BoothifySpacing.md)
                    .padding(.vertical, BoothifySpacing.md)
                }
            }
            .navigationTitle("Connect Twilio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(BoothifyTheme.violet)
                        .font(.subheadline.weight(.semibold))
                }
            }
            .alert("Disconnect Twilio?", isPresented: $confirmDisconnect) {
                Button("Disconnect", role: .destructive) {
                    KeychainStore.clearTwilioCredentials()
                    resultMessage = "Twilio disconnected."
                    resultIsError = false
                    Haptics.notify(.success)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Boothify will stop sending SMS for all events until you reconnect.")
            }
            .onAppear {
                // Pre-fill from existing creds so "Manage" mode is editable.
                if let creds = KeychainStore.loadTwilioCredentials() {
                    accountSid = creds.accountSid
                    authSid = creds.authSid
                    authSecret = creds.authSecret
                    fromNumber = creds.fromNumber
                    kind = creds.kind
                }
            }
        }
    }

    // MARK: - Cards

    private var credentialTypeCard: some View {
        TwilioCard(title: "Credential type") {
            Picker("Credential type", selection: $kind) {
                Text("API Key (recommended)").tag(TwilioCredentials.CredentialKind.apiKey)
                Text("Account SID + Auth Token").tag(TwilioCredentials.CredentialKind.accountToken)
            }
            .pickerStyle(.segmented)
            .padding(.bottom, BoothifySpacing.xs)

            Text(kind == .apiKey
                 ? "API Keys (SK…) are scoped and can be revoked without resetting your whole Twilio account."
                 : "Auth Tokens grant full Twilio account access. Use only for quick testing.")
                .font(.caption)
                .foregroundStyle(BoothifyTheme.textMuted)
        }
    }

    private var credentialsCard: some View {
        TwilioCard(title: "Twilio credentials") {
            TwilioField(placeholder: "Account SID (AC…)", text: $accountSid)
            TwilioDivider()
            if kind == .apiKey {
                TwilioField(placeholder: "API Key SID (SK…)", text: $authSid)
                TwilioDivider()
                TwilioSecureField(placeholder: "API Key Secret", text: $authSecret)
            } else {
                TwilioSecureField(placeholder: "Auth Token", text: $authSecret)
                    .onChange(of: authSecret) { _, _ in authSid = accountSid }
                    .onChange(of: accountSid) { _, _ in authSid = accountSid }
            }
            TwilioDivider()
            TwilioField(
                placeholder: "From number (E.164, e.g. +15555550100)",
                text: $fromNumber,
                keyboardType: .phonePad
            )
        }
    }

    private var actionsCard: some View {
        TwilioCard {
            Button {
                save()
            } label: {
                if sending && resultMessage == nil {
                    HStack(spacing: BoothifySpacing.sm) {
                        ProgressView().tint(.white)
                        Text("Saving…")
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    HStack(spacing: BoothifySpacing.xs) {
                        Image(systemName: "checkmark.seal.fill")
                        Text("Save credentials")
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!canSave || sending)

            Button {
                emailMeInstructions()
            } label: {
                HStack(spacing: BoothifySpacing.xs) {
                    Image(systemName: "envelope.fill")
                    Text("Email me the setup steps")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(SecondaryButtonStyle())
        }
    }

    private var testCard: some View {
        TwilioCard(
            title: "Test SMS",
            subtitle: "Confirm your Twilio number can actually send before going live."
        ) {
            TwilioField(
                placeholder: "Send test to (E.164, e.g. +15555550100)",
                text: $testNumber,
                keyboardType: .phonePad
            )
            TwilioDivider()
            Button {
                sendTest()
            } label: {
                if sending {
                    HStack(spacing: BoothifySpacing.sm) {
                        ProgressView().tint(.white)
                        Text("Sending…")
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    HStack(spacing: BoothifySpacing.xs) {
                        Image(systemName: "paperplane.fill")
                        Text("Send test SMS")
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(sending || testNumber.isEmpty || !canSave)

            if let resultMessage {
                HStack(spacing: BoothifySpacing.xs) {
                    Image(systemName: resultIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .font(.caption)
                    Text(resultMessage)
                        .font(.footnote)
                }
                .foregroundStyle(resultIsError ? BoothifyTheme.error : BoothifyTheme.emerald)
                .padding(.top, BoothifySpacing.xs)
            }
        }
    }

    private var disconnectCard: some View {
        TwilioCard {
            Button(role: .destructive) {
                confirmDisconnect = true
            } label: {
                HStack(spacing: BoothifySpacing.sm) {
                    Image(systemName: "antenna.radiowaves.left.and.right.slash")
                    Text("Disconnect Twilio")
                }
                .frame(maxWidth: .infinity)
                .foregroundStyle(BoothifyTheme.error)
            }
            .buttonStyle(SecondaryButtonStyle())
        }
    }

    // MARK: - Actions

    private func save() {
        let creds = TwilioCredentials(
            accountSid: accountSid.trimmingCharacters(in: .whitespaces),
            authSid: (kind == .accountToken ? accountSid : authSid).trimmingCharacters(in: .whitespaces),
            authSecret: authSecret.trimmingCharacters(in: .whitespaces),
            fromNumber: fromNumber.trimmingCharacters(in: .whitespaces),
            kind: kind
        )
        do {
            try KeychainStore.saveTwilioCredentials(creds)
            resultMessage = "Credentials saved to Keychain."
            resultIsError = false
            Haptics.notify(.success)
        } catch {
            resultMessage = "Couldn't save: \(error.localizedDescription)"
            resultIsError = true
            Haptics.notify(.error)
        }
    }

    private func sendTest() {
        save()
        guard let creds = TwilioClient.shared.currentCredentials() else { return }

        sending = true
        Task {
            do {
                let result = try await TwilioClient.shared.sendSMS(
                    to: testNumber.trimmingCharacters(in: .whitespaces),
                    body: "Boothify test — your Twilio is connected. 🎉",
                    using: creds
                )
                resultMessage = "Test sent (sid \(result.sid ?? "—"))."
                resultIsError = false
                Haptics.notify(.success)
            } catch {
                resultMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                resultIsError = true
                Haptics.notify(.error)
            }
            sending = false
        }
    }

    private func emailMeInstructions() {
        let subject = "Boothify — set up your Twilio for SMS"
        let body = """
        Hi,

        To send AI photos and 360 videos to your guests via SMS, Boothify needs three Twilio values:

        1) Account SID (starts with AC…) — top of https://console.twilio.com
        2) API Key SID (starts with SK…) + API Key Secret — create one at
           https://console.twilio.com/us1/account/keys-credentials/api-keys
           (recommended over the legacy Auth Token because it's scoped and revocable)
        3) A Twilio phone number capable of sending SMS in the regions you'll text guests in.
           Buy one at https://console.twilio.com/us1/develop/phone-numbers/manage/search

        US senders: register A2P 10DLC before going live or Twilio will block your traffic.

        Paste all three into Email / SMS Settings → Connect Twilio in the Boothify app.

        — Boothify
        """
        let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? subject
        let encodedBody = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? body
        if let url = URL(string: "mailto:?subject=\(encodedSubject)&body=\(encodedBody)") {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Reusable sub-components

private struct TwilioCard<Content: View>: View {
    var title: String? = nil
    var subtitle: String? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                VStack(alignment: .leading, spacing: BoothifySpacing.xs) {
                    Text(title.uppercased())
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BoothifyTheme.textMuted)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(BoothifyTheme.textTertiary)
                    }
                }
                .padding(.bottom, BoothifySpacing.xs)
            }
            VStack(alignment: .leading, spacing: BoothifySpacing.sm) {
                content
            }
            .padding(BoothifySpacing.md)
            .boothifySurface(radius: BoothifyRadius.card)
        }
    }
}

private struct TwilioDivider: View {
    var body: some View {
        Rectangle()
            .fill(BoothifyTheme.surfaceLine)
            .frame(height: 1)
    }
}

private struct TwilioField: View {
    let placeholder: String
    let text: Binding<String>
    var keyboardType: UIKeyboardType = .default

    var body: some View {
        TextField(placeholder, text: text)
            .foregroundStyle(.white)
            .font(.system(.subheadline, design: .monospaced))
            .keyboardType(keyboardType)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
    }
}

private struct TwilioSecureField: View {
    let placeholder: String
    let text: Binding<String>

    var body: some View {
        SecureField(placeholder, text: text)
            .foregroundStyle(.white)
            .font(.system(.subheadline, design: .monospaced))
    }
}

#Preview {
    TwilioOnboardingSheet()
}
