import XCTest
import AppKit
@testable import NotchNotifyApp

final class CaptureVisibilityTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        defaults = UserDefaults(suiteName: "CaptureVisibilityTests")!
        defaults.removePersistentDomain(forName: "CaptureVisibilityTests")
    }

    func testDefaultIsHiddenFromCapture() {
        XCTAssertEqual(CaptureVisibility.load(from: defaults), .hidden)
    }

    func testRoundTripsThroughDefaults() {
        CaptureVisibility.visible.save(to: defaults)
        XCTAssertEqual(CaptureVisibility.load(from: defaults), .visible)
        CaptureVisibility.hidden.save(to: defaults)
        XCTAssertEqual(CaptureVisibility.load(from: defaults), .hidden)
    }

    func testToggled() {
        XCTAssertEqual(CaptureVisibility.hidden.toggled, .visible)
        XCTAssertEqual(CaptureVisibility.visible.toggled, .hidden)
    }

    func testMapsToWindowSharingType() {
        XCTAssertEqual(CaptureVisibility.hidden.sharingType, .none)
        XCTAssertEqual(CaptureVisibility.visible.sharingType, .readOnly)
    }
}
