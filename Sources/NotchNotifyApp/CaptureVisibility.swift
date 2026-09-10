import AppKit

/// Whether notification windows show up in screenshots and screen recordings.
/// macOS gates both through one window property (`sharingType`), so there is no
/// "screenshots yes, recordings no" layer; this is a single user-facing toggle.
enum CaptureVisibility: String {
    case hidden
    case visible

    static let defaultsKey = "captureVisibility"

    var sharingType: NSWindow.SharingType {
        switch self {
        case .hidden: return .none
        case .visible: return .readOnly
        }
    }

    var toggled: CaptureVisibility { self == .hidden ? .visible : .hidden }

    static func load(from defaults: UserDefaults = .standard) -> CaptureVisibility {
        defaults.string(forKey: defaultsKey).flatMap(CaptureVisibility.init(rawValue:)) ?? .hidden
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: CaptureVisibility.defaultsKey)
    }
}
