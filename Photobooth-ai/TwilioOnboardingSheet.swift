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
            Form {
                Section {
                    Picker("Credential type", selection: $kind) {
                        Text("API Key (recommended)").tag(TwilioCredentials.CredentialKind.apiKey)
                        Text("Account SID + Auth Token").tag(TwilioCredentials.CredentialKind.accountToken)
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text(kind == .apiKey
                         ? "API Keys (SK…) are scoped and can be revoked without resetting your whole Twilio account."
                         : "Auth Tokens grant full Twilio account access. Use only for quick testing.")
                        .font(.caption2)
                }

                Section("Twilio credentials") {
                    TextField("Account SID (AC…)", text: $accountSid)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .font(.system(.body, design: .monospaced))
                    if kind == .apiKey {
                        TextField("API Key SID (SK…)", text: $authSid)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .font(.system(.body, design: .monospaced))
                        SecureField("API Key Secret", text: $authSecret)
                    } else {
                        SecureField("Auth Token", text: $authSecret)
                            .onChange(of: authSecret) { _, _ in
                                // Account-token flow uses Account SID as the auth SID too.
                                authSid = accountSid
                            }
                            .onChange(of: accountSid) { _, _ in
                                authSid = accountSid
                            }
                    }
                    TextField("From number (E.164, e.g. +15555550100)", text: $fromNumber)
                        .keyboardType(.phonePad)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section {
                    Button {
                        save()
                    } label: {
                        if sending && resultMessage == nil {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("Saving…")
                            }
                        } else {
                            Label("Save credentials", systemImage: "checkmark.seal.fill")
                        }
                    }
                    .disabled(!canSave || sending)

                    Button {
                        emailMeInstructions()
                    } label: {
                        Label("Email me the setup steps", systemImage: "envelope.fill")
                    }
                }

                Section("Test SMS") {
                    TextField("Send test to (E.164)", text: $testNumber)
                        .keyboardType(.phonePad)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button {
                        sendTest()
                    } label: {
                        if sending {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("Sending…")
                            }
                        } else {
                            Label("Send test SMS", systemImage: "paperplane.fill")
                        }
                    }
                    .disabled(sending || testNumber.isEmpty || !canSave)
                    if let resultMessage {
                        Text(resultMessage)
                            .font(.footnote)
                            .foregroundStyle(resultIsError ? .red.opacity(0.9) : BoothifyTheme.emerald)
                    }
                }

                if KeychainStore.loadTwilioCredentials() != nil {
                    Section {
                        Button(role: .destructive) {
                            confirmDisconnect = true
                        } label: {
                            Label("Disconnect Twilio", systemImage: "antenna.radiowaves.left.and.right.slash")
                        }
                    }
                }
            }
            .navigationTitle("Connect Twilio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
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
        // Save first if not yet — operator might want to test before deciding
        // to keep credentials. We always persist so a successful test confirms
        // they're stored.
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

    /// Open the system mail compose via `mailto:` — universal, doesn't require
    /// MFMailComposeViewController which silently fails when Mail.app is
    /// unconfigured.
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

#Preview {
    TwilioOnboardingSheet()
}
