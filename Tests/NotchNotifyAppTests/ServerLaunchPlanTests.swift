import XCTest
@testable import notch_cli

final class ServerLaunchPlanTests: XCTestCase {
    func testUsesDirectProcessLaunchForServerBinary() {
        let serverURL = URL(fileURLWithPath: "/usr/local/bin/NotchNotifyApp")
        let plan = ServerLaunchPlan.make(for: serverURL)

        XCTAssertEqual(plan.executableURL, serverURL)
        XCTAssertEqual(plan.arguments, [])
    }
}
