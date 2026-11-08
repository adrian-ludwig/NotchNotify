import XCTest
@testable import notch_cli

final class CLIOpenURLTests: XCTestCase {
    func testAcceptsHttpAndHttpsURLs() {
        XCTAssertEqual(OpenURL.parse("https://github.com/org/repo/pull/42")?.absoluteString,
                       "https://github.com/org/repo/pull/42")
        XCTAssertNotNil(OpenURL.parse("http://localhost:8080/x"))
        XCTAssertNotNil(OpenURL.parse("HTTPS://example.com"))
    }

    func testRejectsNonWebOrMalformedURLs() {
        for value in ["file:///etc/passwd", "javascript:alert(1)", "ftp://example.com",
                      "example.com/pr/1", "https://", "not a url", ""] {
            XCTAssertNil(OpenURL.parse(value), value)
        }
    }

    func testRequestEncodesURLOnlyWhenSet() throws {
        let plain = NotifyRequest(title: "T", subtitle: nil, body: nil, image: nil,
                                  actions: ["Open PR"], timeout: nil, style: nil, accentHex: nil)
        let withURL = NotifyRequest(title: "T", subtitle: nil, body: nil, image: nil,
                                    actions: ["Open PR"], timeout: nil, style: nil, accentHex: nil,
                                    url: "https://example.com/pr/1")

        let plainJSON = try XCTUnwrap(String(data: JSONEncoder().encode(plain), encoding: .utf8))
        let urlJSON = try XCTUnwrap(String(data: JSONEncoder().encode(withURL), encoding: .utf8))
        XCTAssertFalse(plainJSON.contains("\"url\""))
        XCTAssertTrue(urlJSON.contains("\"url\":\"https:\\/\\/example.com\\/pr\\/1\""))
    }

    func testDecodesResponseFromOlderAppWithoutClickedAt() throws {
        let json = #"{"action":"Accept","dismissed":false}"#
        let response = try JSONDecoder().decode(NotifyResponse.self, from: Data(json.utf8))
        XCTAssertEqual(response.action, "Accept")
        XCTAssertFalse(response.dismissed)
        XCTAssertNil(response.clickedAt)
    }

    func testDecodesResponseWithClickedAt() throws {
        let json = #"{"action":"Accept","dismissed":false,"clickedAt":"2026-11-08T09:15:02Z"}"#
        let response = try JSONDecoder().decode(NotifyResponse.self, from: Data(json.utf8))
        XCTAssertEqual(response.clickedAt, "2026-11-08T09:15:02Z")
    }
}
