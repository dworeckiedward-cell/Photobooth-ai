import XCTest
@testable import Photobooth_ai

/// Characterization: which failures the app treats as retryable. Queues and
/// pollers key off this — silently flipping a case would change replay
/// semantics event-wide.
final class APIErrorMappingTests: XCTestCase {

    func testRetryableCases() {
        XCTAssertTrue(APIError.network(URLError(.timedOut)).isRetryable)
        XCTAssertTrue(APIError.serverError(status: 503, message: nil).isRetryable)
        XCTAssertTrue(APIError.rateLimited(resetIn: 1000).isRetryable)
        XCTAssertTrue(APIError.pollingTimedOut.isRetryable)
    }

    func testNonRetryableCases() {
        XCTAssertFalse(APIError.invalidURL.isRetryable)
        XCTAssertFalse(APIError.unauthorized.isRetryable)
        XCTAssertFalse(APIError.clientError(status: 400, message: nil).isRetryable)
        XCTAssertFalse(APIError.generationFailed(kind: "quota_exceeded", message: "x").isRetryable)
        XCTAssertFalse(
            APIError.decoding(NSError(domain: "test", code: 1)).isRetryable
        )
    }
}
