import XCTest
@testable import NotchNotifyApp

final class ActionOutcomeTests: XCTestCase {
    private func request(url: String?) -> NotifyRequest {
        NotifyRequest(title: "PR ready", subtitle: nil, body: nil, image: nil,
                      actions: ["Open PR", "Later"], timeout: nil, style: nil, accentHex: nil,
                      url: url)
    }

    func testDecodesRequestFromOlderCLIWithoutURL() throws {
        let json = #"{"title":"T","actions":["OK"]}"#
        let req = try JSONDecoder().decode(NotifyRequest.self, from: Data(json.utf8))
        XCTAssertEqual(req.actions, ["OK"])
        XCTAssertNil(req.url)
    }

    func testDecodesRequestWithURL() throws {
        let json = #"{"title":"T","actions":["OK"],"url":"https://example.com/pr/1"}"#
        let req = try JSONDecoder().decode(NotifyRequest.self, from: Data(json.utf8))
        XCTAssertEqual(req.url, "https://example.com/pr/1")
    }

    func testActionResponseCarriesISO8601ClickTime() throws {
        let date = Date(timeIntervalSince1970: 1_793_000_000)
        let response = ActionOutcome.response(action: "Later", dismissed: false, at: date)
        XCTAssertEqual(response.action, "Later")
        XCTAssertFalse(response.dismissed)
        let clickedAt = try XCTUnwrap(response.clickedAt)
        XCTAssertEqual(ISO8601DateFormatter().date(from: clickedAt), date)
    }

    func testDismissedResponseHasNoActionOrClickTime() throws {
        let response = ActionOutcome.response(action: nil, dismissed: true, at: Date())
        XCTAssertNil(response.action)
        XCTAssertTrue(response.dismissed)
        XCTAssertNil(response.clickedAt)

        let json = try XCTUnwrap(String(data: JSONEncoder().encode(response), encoding: .utf8))
        XCTAssertFalse(json.contains("clickedAt"))
    }

    func testOpensURLOnlyForFirstAction() {
        let req = request(url: "https://example.com/pr/1")
        XCTAssertEqual(ActionOutcome.urlToOpen(for: req, action: "Open PR")?.absoluteString,
                       "https://example.com/pr/1")
        XCTAssertNil(ActionOutcome.urlToOpen(for: req, action: "Later"))
        XCTAssertNil(ActionOutcome.urlToOpen(for: req, action: nil))
    }

    func testOpensNothingWithoutAValidWebURL() {
        XCTAssertNil(ActionOutcome.urlToOpen(for: request(url: nil), action: "Open PR"))
        XCTAssertNil(ActionOutcome.urlToOpen(for: request(url: "file:///etc/passwd"), action: "Open PR"))
    }
}
