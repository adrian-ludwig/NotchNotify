import XCTest
@testable import NotchNotifyApp

final class NotchScreenSelectorTests: XCTestCase {
    func testMainFirstModePrefersMainScreenEvenWhenAnotherScreenHasNotch() {
        let screens = [
            NotchScreenSelector.ScreenCandidate(isMain: false, hasNotch: true),
            NotchScreenSelector.ScreenCandidate(isMain: true, hasNotch: false),
        ]

        XCTAssertEqual(NotchScreenSelector.targetIndex(in: screens, mode: .main), 1)
    }

    func testNotchFirstModePrefersNotchedScreenEvenWhenAnotherScreenIsMain() {
        let screens = [
            NotchScreenSelector.ScreenCandidate(isMain: true, hasNotch: false),
            NotchScreenSelector.ScreenCandidate(isMain: false, hasNotch: true),
        ]

        XCTAssertEqual(NotchScreenSelector.targetIndex(in: screens, mode: .notch), 1)
    }

    func testMainFirstModeFallsBackToNotchedScreenWhenNoMainScreenExists() {
        let screens = [
            NotchScreenSelector.ScreenCandidate(isMain: false, hasNotch: false),
            NotchScreenSelector.ScreenCandidate(isMain: false, hasNotch: true),
        ]

        XCTAssertEqual(NotchScreenSelector.targetIndex(in: screens, mode: .main), 1)
    }

    func testFallsBackToFirstScreenWhenNothingElseMatches() {
        let screens = [
            NotchScreenSelector.ScreenCandidate(isMain: false, hasNotch: false),
            NotchScreenSelector.ScreenCandidate(isMain: false, hasNotch: false),
        ]

        XCTAssertEqual(NotchScreenSelector.targetIndex(in: screens, mode: .main), 0)
    }

    func testScreenTargetModeFromEnvDefaultsToMain() {
        XCTAssertEqual(ScreenTargetMode.fromEnv([:]), .main)
        XCTAssertEqual(ScreenTargetMode.fromEnv(["NOTCH_SCREEN_TARGET": "unknown"]), .main)
    }

    func testScreenTargetModeFromEnvParsesNotchOverride() {
        XCTAssertEqual(ScreenTargetMode.fromEnv(["NOTCH_SCREEN_TARGET": "notch"]), .notch)
    }

    func testEffectiveNotchModeUsesTargetScreenInAutoMode() {
        XCTAssertFalse(EffectiveNotchMode.resolve(notchMode: .auto, targetScreenHasNotch: false))
        XCTAssertTrue(EffectiveNotchMode.resolve(notchMode: .auto, targetScreenHasNotch: true))
    }

    func testEffectiveNotchModeRespectsExplicitOverrides() {
        XCTAssertTrue(EffectiveNotchMode.resolve(notchMode: .on, targetScreenHasNotch: false))
        XCTAssertFalse(EffectiveNotchMode.resolve(notchMode: .off, targetScreenHasNotch: true))
    }

    func testNotchModeDefaultHeightMatchesFullMenuBarInset() {
        XCTAssertEqual(NotchMode.defaultHeight, 38)
    }
}
