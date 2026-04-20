import Foundation
import Darwin

// Usage:
//   notch "Title"
//        [--subtitle "Subtitle"] [--body "Longer description"]
//        [--image PATH | sf:symbol.name]
//        [--actions A,B,C] [--timeout SECS] [--style glass|solid]
//        [--accent #RRGGBB]
//
// Exit codes:
//   0  first action clicked
//   1  non-first action clicked
//   2  dismissed / timed out
//   3  couldn't reach the app

struct CLI {
    static func run() -> Int32 {
        var args = Array(CommandLine.arguments.dropFirst())
        guard !args.isEmpty else { printUsage(); return 3 }

        if args.first == "--help" || args.first == "-h" {
            printUsage(); return 0
        }

        let title = args.removeFirst()
        var subtitle: String?
        var body: String?
        var image: String?
        var actions: [String] = []
        var timeout: Double?
        var style: String?
        var accent: String?

        while !args.isEmpty {
            let flag = args.removeFirst()
            func next(_ name: String) -> String? {
                guard !args.isEmpty else {
                    FileHandle.standardError.write(Data("Missing value for \(name)\n".utf8))
                    return nil
                }
                return args.removeFirst()
            }

            switch flag {
            case "--subtitle", "-s":
                guard let v = next(flag) else { return 3 }; subtitle = v
            case "--body", "-b":
                guard let v = next(flag) else { return 3 }; body = v
            case "--image", "-i":
                guard let v = next(flag) else { return 3 }; image = v
            case "--actions", "-a":
                guard let v = next(flag) else { return 3 }
                actions = v.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
            case "--timeout", "-t":
                guard let v = next(flag) else { return 3 }; timeout = Double(v)
            case "--style":
                guard let v = next(flag) else { return 3 }; style = v
            case "--accent":
                guard let v = next(flag) else { return 3 }; accent = v
            case "--help", "-h":
                printUsage(); return 0
            default:
                FileHandle.standardError.write(Data("Unknown flag: \(flag)\n".utf8))
                return 3
            }
        }

        let req = NotifyRequest(
            title: title,
            subtitle: subtitle,
            body: body,
            image: image,
            actions: actions,
            timeout: timeout,
            style: style,
            accentHex: accent
        )

        ensureServerRunning()

        guard let response = send(req) else {
            FileHandle.standardError.write(Data("Could not reach NotchNotify app.\n".utf8))
            return 3
        }

        if let data = try? JSONEncoder().encode(response),
           let json = String(data: data, encoding: .utf8) {
            print(json)
        }

        if response.dismissed { return 2 }
        if let action = response.action, let first = actions.first, action == first { return 0 }
        return 1
    }

    static func ensureServerRunning() {
        guard !canConnect() else { return }

        guard let serverURL = findServer() else { return }

        let launchPlan = ServerLaunchPlan.make(for: serverURL)
        let p = Process()
        p.executableURL = launchPlan.executableURL
        p.arguments = launchPlan.arguments
        p.standardInput = FileHandle.nullDevice
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()

        // Wait up to 5s for socket
        for _ in 0..<50 {
            usleep(100_000)
            if canConnect() { return }
        }
    }

    static func findServer() -> URL? {
        // 1. Real path of this binary via kernel API (works regardless of argv[0])
        var buf = [CChar](repeating: 0, count: Int(PATH_MAX))
        var len = UInt32(PATH_MAX)
        if _NSGetExecutablePath(&buf, &len) == 0 {
            let real = URL(fileURLWithPath: String(cString: buf)).resolvingSymlinksInPath()
            let candidate = real.deletingLastPathComponent().appendingPathComponent("NotchNotifyApp")
            if FileManager.default.isExecutableFile(atPath: candidate.path) { return candidate }
        }
        // 2. Search PATH directories
        let dirs = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        for dir in dirs {
            let candidate = URL(fileURLWithPath: dir).appendingPathComponent("NotchNotifyApp")
            if FileManager.default.isExecutableFile(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    static func canConnect() -> Bool {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let cap = MemoryLayout.size(ofValue: addr.sun_path)
        _ = SocketPath.path.withCString { src in
            withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
                ptr.withMemoryRebound(to: CChar.self, capacity: cap) { dst in
                    strncpy(dst, src, cap - 1)
                }
            }
        }
        let len = socklen_t(MemoryLayout<sockaddr_un>.size)
        return withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, len) == 0 }
        }
    }

    static func send(_ request: NotifyRequest) -> NotifyResponse? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathCapacity = MemoryLayout.size(ofValue: addr.sun_path)
        _ = SocketPath.path.withCString { src in
            withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
                ptr.withMemoryRebound(to: CChar.self, capacity: pathCapacity) { dst in
                    strncpy(dst, src, pathCapacity - 1)
                }
            }
        }

        let len = socklen_t(MemoryLayout<sockaddr_un>.size)
        let ok = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, len) }
        }
        guard ok == 0 else { return nil }

        guard var payload = try? JSONEncoder().encode(request) else { return nil }
        payload.append(0x0A)
        let wrote = payload.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
        guard wrote == payload.count else { return nil }

        var buffer = Data()
        var byte: UInt8 = 0
        while read(fd, &byte, 1) == 1 {
            if byte == 0x0A { break }
            buffer.append(byte)
        }
        return try? JSONDecoder().decode(NotifyResponse.self, from: buffer)
    }

    static func printUsage() {
        let usage = """
        NotchNotify CLI

        USAGE:
          notch "Title" [options]

        OPTIONS:
          -s, --subtitle TEXT     Small secondary line under the title
          -b, --body TEXT         Longer description
          -i, --image VALUE       Emoji 🚀, file path, https:// URL, or sf:symbol.name
          -a, --actions A,B,C     Comma-separated action buttons
          -t, --timeout SECS      Auto-dismiss after N seconds
              --style glass|solid Visual style (default: glass)
              --accent #RRGGBB    Primary button color
          -h, --help              Show this help

        EXAMPLES:
          notch "Build complete"
          notch "Deploy ready" -s "main branch" -b "Push to prod?" -a Deploy,Cancel
          notch "New DM" -i ~/avatars/alice.png -b "hey, you around?" -a Reply,Later
          notch "Agent" -i sf:sparkles -b "Run tests before commit?" -a Yes,No -t 30

        EXIT CODES:
          0 first action, 1 other action, 2 dismissed, 3 error
        """
        print(usage)
    }
}

exit(CLI.run())
