import Foundation

// Request: CLI -> App
struct NotifyRequest: Codable {
    let title: String
    let subtitle: String?
    let body: String?
    let image: String?          // path to image file, OR an SF Symbol name (prefix "sf:")
    let actions: [String]       // e.g. ["Accept", "Decline"]
    let timeout: Double?        // seconds; nil = no auto-dismiss
    let style: String?          // "glass" | "solid" (default glass)
    let accentHex: String?      // primary button color, e.g. "#FF5E5E"
    var url: String? = nil      // http(s) link the app opens when the first action is clicked
}

// Response: App -> CLI
struct NotifyResponse: Codable {
    let action: String?         // which button was clicked, or nil if dismissed
    let dismissed: Bool         // true if timed out or closed without action
    var clickedAt: String? = nil // ISO-8601 time of the click; nil when dismissed
}

enum OpenURL {
    /// The URL for `--open-url`, or nil unless it parses with an http or https scheme and a host.
    static func parse(_ value: String) -> URL? {
        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty
        else { return nil }
        return url
    }
}

enum SocketPath {
    /// Directory containing the socket. Respects XDG_CONFIG_HOME if set.
    static var directory: String {
        if let xdg = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"], !xdg.isEmpty {
            return "\(xdg)/NotchNotify"
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.config/NotchNotify"
    }

    /// Full path to the Unix domain socket.
    static var path: String { "\(directory)/connect.socket" }

    /// Ensure the containing directory exists. Called by the server before bind.
    static func ensureDirectory() throws {
        try FileManager.default.createDirectory(
            atPath: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
    }
}
