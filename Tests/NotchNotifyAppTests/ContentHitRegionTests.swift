import XCTest
@testable import NotchNotifyApp

final class ContentHitRegionTests: XCTestCase {
    private let bounds = CGRect(x: 0, y: 0, width: 520, height: 320)
    private let content = CGSize(width: 460, height: 120)

    func testFlippedViewAnchorsContentAtTopLeftOrigin() {
        let rect = ContentHitRegion.rect(bounds: bounds, contentSize: content, flipped: true)
        XCTAssertEqual(rect, CGRect(x: 30, y: 0, width: 460, height: 120))
    }

    func testUnflippedViewAnchorsContentAtMaxY() {
        let rect = ContentHitRegion.rect(bounds: bounds, contentSize: content, flipped: false)
        XCTAssertEqual(rect, CGRect(x: 30, y: 200, width: 460, height: 120))
    }

    func testUnknownContentSizeMeansNoHitRegion() {
        XCTAssertNil(ContentHitRegion.rect(bounds: bounds, contentSize: .zero, flipped: true))
        XCTAssertNil(ContentHitRegion.rect(bounds: bounds, contentSize: CGSize(width: 1, height: 1), flipped: true))
    }

    func testContentLargerThanBoundsIsClamped() {
        let big = CGSize(width: 900, height: 900)
        XCTAssertEqual(ContentHitRegion.rect(bounds: bounds, contentSize: big, flipped: true), bounds)
        XCTAssertEqual(ContentHitRegion.rect(bounds: bounds, contentSize: big, flipped: false), bounds)
    }

    func testContainsInFlippedCoordinates() {
        XCTAssertTrue(ContentHitRegion.contains(CGPoint(x: 260, y: 60), bounds: bounds, contentSize: content, flipped: true))
        XCTAssertFalse(ContentHitRegion.contains(CGPoint(x: 260, y: 250), bounds: bounds, contentSize: content, flipped: true))
        XCTAssertFalse(ContentHitRegion.contains(CGPoint(x: 10, y: 60), bounds: bounds, contentSize: content, flipped: true))
    }

    func testUnknownContentSizeContainsNothing() {
        XCTAssertFalse(ContentHitRegion.contains(CGPoint(x: 260, y: 60), bounds: bounds, contentSize: .zero, flipped: true))
    }
}
