import XCTest
@testable import NotchNotifyApp

final class QueueBarStyleTests: XCTestCase {
    func testUsesTighterGapUnderCard() {
        XCTAssertEqual(QueueBarStyle.stackSpacing, 4)
    }

    func testMatchesCardShadowProfile() {
        XCTAssertEqual(QueueBarStyle.shadowRadius, 20)
        XCTAssertEqual(QueueBarStyle.shadowYOffset, 8)
    }
}
