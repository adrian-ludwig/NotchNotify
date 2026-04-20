import Foundation

enum ScreenTargetMode: String {
    case main
    case notch

    static func fromEnv(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> ScreenTargetMode {
        let raw = environment["NOTCH_SCREEN_TARGET"]?.lowercased() ?? ""
        return ScreenTargetMode(rawValue: raw) ?? .main
    }
}

struct NotchScreenSelector {
    struct ScreenCandidate: Equatable {
        let isMain: Bool
        let hasNotch: Bool
    }

    static func targetIndex(in screens: [ScreenCandidate], mode: ScreenTargetMode) -> Int? {
        switch mode {
        case .main:
            return screens.firstIndex(where: \.isMain)
                ?? screens.firstIndex(where: \.hasNotch)
                ?? screens.indices.first
        case .notch:
            return screens.firstIndex(where: \.hasNotch)
                ?? screens.firstIndex(where: \.isMain)
                ?? screens.indices.first
        }
    }
}
