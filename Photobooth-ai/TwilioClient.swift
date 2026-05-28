import Foundation

/// Per-operator Twilio credentials. iOS stores these in Keychain and uses them
/// to send SMS directly to Twilio REST API — no backend brokering. Operator
/// can use either:
///
/// - **Account SID + Auth Token** (works, but the Auth Token is god-mode for
///   their entire Twilio account — recommend API Key for production).
/// - **API Key SID (SK…) + API Key Secret** (scoped, revocable, recommended).
///
/// Wire is identical for both flows: HTTP Basic Auth with `sid:secret`. The
/// only difference is whether `sid` starts with `AC` (Account) or `SK` (API
/// Key). When it's a Key SID, the REST URL still uses the Account SID — so we
/// store that separately as `accountSid` and reuse it for the path.
struct TwilioCredentials: Codable, Equatable, Sendable {
    enum CredentialKind: String, Codable, Sendable {
        case accountToken   // Account SID + Auth Token (legacy, not recommended)
        case apiKey         // API Key SID (SK...) + API Key Secret (preferred)
    }

    /// Twilio Account SID (always starts with `AC...`). Used in the REST URL.
    var accountSid: String
    /// `accountSid` when kind == .accountToken; the API Key SID (`SK...`)
    /// when kind == .apiKey.
    var authSid: String
    /// Auth Token (account) or API Key Secret (key). Both are sensitive.
    var authSecret: String
    /// Twilio-provisioned phone number used as the SMS `From` value. E.164.
    var fromNumber: String
    var kind: CredentialKind

    /// True when all four fields look populated. We don't deeply validate —
    /// Twilio will reject malformed values with a clear API error.
    var isConfigured: Bool {
        !accountSid.isEmpty && !authSid.isEmpty && !authSecret.isEmpty && !fromNumber.isEmpty
    }
}

/// Direct Twilio REST client. No SDK — Basic Auth + URLSession is enough.
///
/// Errors decode the Twilio error envelope so the wizard can show actionable
/// messages (unverified number, insufficient funds, bad auth, etc.) instead
/// of opaque HTTP codes.
@MainActor
final class TwilioClient {
    static let shared = TwilioClient()

    private let session: URLSession
    private let jsonDecoder: JSONDecoder

    private init() {
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = false
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: config)
        self.jsonDecoder = JSONDecoder()
    }

    /// Returns the persisted credentials, if any. Convenience wrapper around
    /// Keychain so callers don't reach in directly.
    func currentCredentials() -> TwilioCredentials? {
        KeychainStore.loadTwilioCredentials()
    }

    /// POST https://api.twilio.com/2010-04-01/Accounts/{Account SID}/Messages.json
    /// `From` defaults to the credential's `fromNumber`; per-event override via
    /// the explicit `fromOverride` argument.
    func sendSMS(
        to phoneE164: String,
        body: String,
        using credentials: TwilioCredentials,
        fromOverride: String? = nil
    ) async throws -> TwilioMessageResponse {
        guard credentials.isConfigured else {
            throw TwilioError.notConfigured
        }
        let from = (fromOverride?.isEmpty == false) ? fromOverride! : credentials.fromNumber

        let urlString = "https://api.twilio.com/2010-04-01/Accounts/\(credentials.accountSid)/Messages.json"
        guard let url = URL(string: urlString) else { throw TwilioError.invalidURL }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        // Basic Auth = base64(sid:secret). Works identically for Account SID +
        // Auth Token AND API Key SID + Secret.
        let credString = "\(credentials.authSid):\(credentials.authSecret)"
        guard let credData = credString.data(using: .utf8) else { throw TwilioError.invalidURL }
        let basic = credData.base64EncodedString()
        req.setValue("Basic \(basic)", forHTTPHeaderField: "Authorization")

        let form = [
            "To": phoneE164,
            "From": from,
            "Body": body,
        ]
        req.httpBody = Self.formEncode(form).data(using: .utf8)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: req)
        } catch let urlError as URLError {
            throw TwilioError.network(urlError)
        }

        guard let http = response as? HTTPURLResponse else {
            throw TwilioError.badResponse(status: 0, message: "Non-HTTP response")
        }

        if (200..<300).contains(http.statusCode) {
            let parsed = try jsonDecoder.decode(TwilioMessageResponse.self, from: data)
            return parsed
        }

        // Twilio errors decode cleanly with { code, message, more_info, status }.
        if let envelope = try? jsonDecoder.decode(TwilioErrorEnvelope.self, from: data) {
            throw TwilioError.twilio(code: envelope.code,
                                      message: envelope.message,
                                      moreInfo: envelope.moreInfo)
        }
        throw TwilioError.badResponse(status: http.statusCode,
                                      message: String(data: data, encoding: .utf8) ?? "Unknown error")
    }

    private static func formEncode(_ fields: [String: String]) -> String {
        fields.map { key, value in
            let k = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key
            let v = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
            return "\(k)=\(v)"
        }
        .joined(separator: "&")
    }
}

// MARK: - Wire models

struct TwilioMessageResponse: Decodable {
    let sid: String?
    let status: String?
    let to: String?
    let from: String?
    let body: String?
    let errorCode: Int?
    let errorMessage: String?

    enum CodingKeys: String, CodingKey {
        case sid, status, to, from, body
        case errorCode = "error_code"
        case errorMessage = "error_message"
    }
}

private struct TwilioErrorEnvelope: Decodable {
    let code: Int?
    let message: String?
    let moreInfo: String?
    let status: Int?

    enum CodingKeys: String, CodingKey {
        case code, message, status
        case moreInfo = "more_info"
    }
}

// MARK: - Errors

enum TwilioError: LocalizedError {
    case notConfigured
    case invalidURL
    case network(URLError)
    case badResponse(status: Int, message: String)
    case twilio(code: Int?, message: String?, moreInfo: String?)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Twilio is not connected yet. Add your credentials in Email / SMS settings."
        case .invalidURL:
            return "Twilio request couldn't be built."
        case .network(let err):
            return err.localizedDescription
        case .badResponse(let status, let message):
            return "Twilio returned HTTP \(status). \(message)"
        case .twilio(let code, let message, _):
            // Common error codes:
            //  21211 invalid To, 21408 unverified trial number, 21610 STOP'd,
            //  21614 not SMS-capable, 21651 region not enabled.
            if let code, let message {
                return "Twilio \(code): \(message)"
            }
            return message ?? "Twilio rejected the message."
        }
    }
}
