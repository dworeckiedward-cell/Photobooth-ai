import XCTest
@testable import Photobooth_ai

/// PHASE 7 GATE A: delivery routing (SMS = link, always), file-size targeting,
/// and the deferred-resolve contract (share link known at SIGN time, before
/// the upload finishes — the guest never waits on a live upload).
final class DeliveryPolicyTests: XCTestCase {

    // MARK: - SMS is a LINK channel

    func testSMSBodyFillsTemplatePlaceholders() {
        let link = URL(string: "https://boothify.app/v/abc123")!
        let body = DeliveryPolicy.smsBody(
            template: "Your spin from {{eventName}} is ready: {{link}}",
            link: link, eventName: "Anna & Tom"
        )
        XCTAssertEqual(body, "Your spin from Anna & Tom is ready: https://boothify.app/v/abc123")
    }

    func testSMSBodyGuaranteesLinkEvenWhenTemplateDropsIt() {
        let link = URL(string: "https://boothify.app/v/abc123")!
        let body = DeliveryPolicy.smsBody(
            template: "Thanks for visiting {{eventName}}!",
            link: link, eventName: "Gala"
        )
        XCTAssertTrue(body.contains(link.absoluteString),
                      "an SMS without the link delivers NOTHING — policy must append it")
    }

    // MARK: - File-size targeting

    func testOversizedBestQualityFallsBackToFastShare() {
        XCTAssertTrue(DeliveryPolicy.shouldFallbackToFastShare(bytes: 20_000_000, preset: .bestQuality))
        XCTAssertFalse(DeliveryPolicy.shouldFallbackToFastShare(bytes: 12_000_000, preset: .bestQuality),
                       "within budget — no fallback")
        XCTAssertFalse(DeliveryPolicy.shouldFallbackToFastShare(bytes: 20_000_000, preset: .fastShare),
                       "fast share is already the floor — nothing to fall back to")
    }

    // MARK: - Deferred resolve (sign-time link)

    func testSignResponseCarriesThePublicLinkUpfront() throws {
        // The wire format of POST /api/booth360/uploads/sign — the contract
        // that makes deferred-resolve possible. If `public_share_url` ever
        // leaves the sign response, the guest goes back to waiting on uploads.
        let json = Data("""
        {
          "upload_url": "https://storage.example.com/signed",
          "upload_token": "tok",
          "storage_path": "events/x/clip.mp4",
          "short_code": "abc123",
          "public_share_url": "https://boothify.app/v/abc123",
          "expected_content_type": "video/mp4"
        }
        """.utf8)
        let response = try JSONDecoder().decode(BoothifyAPI.UploadURLResponse.self, from: json)
        XCTAssertEqual(response.publicShareURL.absoluteString, "https://boothify.app/v/abc123")
        XCTAssertEqual(response.shortCode, "abc123")
    }
}
