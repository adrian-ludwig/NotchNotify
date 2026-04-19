import SwiftUI
import AppKit

// MARK: - App entry

@main
struct NotchNotifyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene {
        Settings { EmptyView() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var server: SocketServer!
    private var presenter: NotchPresenter!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        presenter = NotchPresenter()
        server = SocketServer(presenter: presenter)
        server.start()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "bell.badge.fill", accessibilityDescription: "NotchNotify")
        }
        let menu = NSMenu()
        menu.addItem(withTitle: "Test Notification", action: #selector(testNotify), keyEquivalent: "t")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Quit NotchNotify", action: #selector(quit), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        statusItem.menu = menu
    }

    @objc func testNotify() {
        let req = NotifyRequest(
            title: "Deploy finished",
            subtitle: "production · main branch",
            body: "All checks passed. Ready to roll out to users?",
            image: "sf:checkmark.seal.fill",
            actions: ["Accept", "Decline"],
            timeout: 12,
            style: "glass",
            accentHex: nil
        )
        presenter.present(req) { _ in }
    }

    @objc func quit() { NSApp.terminate(nil) }
}

// MARK: - Socket server
// One connection = one notification. CLI sends a JSON line, reads a JSON line back.

final class SocketServer {
    private let presenter: NotchPresenter
    private var listener: Int32 = -1
    private let queue = DispatchQueue(label: "notchnotify.server", qos: .userInitiated)

    init(presenter: NotchPresenter) { self.presenter = presenter }

    func start() {
        do {
            try SocketPath.ensureDirectory()
        } catch {
            NSLog("Failed to create socket directory: \(error)")
            return
        }

        let path = SocketPath.path
        unlink(path)

        listener = socket(AF_UNIX, SOCK_STREAM, 0)
        guard listener >= 0 else { NSLog("socket() failed"); return }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        _ = path.withCString { src in
            withUnsafeMutablePointer(to: &addr.sun_path) {
                $0.withMemoryRebound(to: CChar.self, capacity: MemoryLayout.size(ofValue: addr.sun_path)) { dst in
                    strncpy(dst, src, MemoryLayout.size(ofValue: addr.sun_path) - 1)
                }
            }
        }

        let len = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(listener, $0, len) }
        }
        guard bindResult == 0 else {
            NSLog("bind() failed: \(String(cString: strerror(errno)))"); return
        }
        guard Darwin.listen(listener, 8) == 0 else { NSLog("listen() failed"); return }
        chmod(path, 0o600)

        queue.async { [weak self] in self?.acceptLoop() }
    }

    private func acceptLoop() {
        while true {
            let client = accept(listener, nil, nil)
            if client < 0 { continue }
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.handle(client: client)
            }
        }
    }

    private func handle(client: Int32) {
        defer { close(client) }
        guard let line = readLine(fd: client), let data = line.data(using: .utf8) else { return }
        guard let req = try? JSONDecoder().decode(NotifyRequest.self, from: data) else {
            _ = writeJSON(fd: client, NotifyResponse(action: nil, dismissed: true))
            return
        }

        let sem = DispatchSemaphore(value: 0)
        var result = NotifyResponse(action: nil, dismissed: true)
        DispatchQueue.main.async { [weak self] in
            self?.presenter.present(req) { response in
                result = response
                sem.signal()
            }
        }
        sem.wait()
        _ = writeJSON(fd: client, result)
    }

    private func readLine(fd: Int32) -> String? {
        var buffer = Data()
        var byte: UInt8 = 0
        while read(fd, &byte, 1) == 1 {
            if byte == 0x0A { break }
            buffer.append(byte)
        }
        return String(data: buffer, encoding: .utf8)
    }

    private func writeJSON<T: Encodable>(fd: Int32, _ value: T) -> Bool {
        guard var data = try? JSONEncoder().encode(value) else { return false }
        data.append(0x0A)
        return data.withUnsafeBytes { buf in
            write(fd, buf.baseAddress, buf.count) == buf.count
        }
    }
}

// MARK: - Presenter

final class NotchPresenter {
    private var currentWindow: NotchWindow?

    func present(_ request: NotifyRequest, completion: @escaping (NotifyResponse) -> Void) {
        currentWindow?.dismissImmediately()
        let window = NotchWindow(request: request) { [weak self] response in
            completion(response)
            self?.currentWindow = nil
        }
        currentWindow = window
        window.show()
    }
}

// MARK: - Notch window
// Borderless, transparent, floating panel pinned to top-center of the main screen.
// Critical: sharingType = .none makes this invisible to screen recording.

final class NotchWindow: NSPanel {
    private let request: NotifyRequest
    private let completion: (NotifyResponse) -> Void
    private var didComplete = false
    private var dismissTimer: Timer?

    init(request: NotifyRequest, completion: @escaping (NotifyResponse) -> Void) {
        self.request = request
        self.completion = completion

        let screen = NSScreen.main ?? NSScreen.screens.first!
        // Size is a starting box; SwiftUI will lay out within it.
        let size = NSSize(width: 460, height: 210)
        let screenFrame = screen.frame
        let x = screenFrame.midX - size.width / 2
        let y = screenFrame.maxY - size.height
        let frame = NSRect(x: x, y: y, width: size.width, height: size.height)

        super.init(contentRect: frame,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)

        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.level = .screenSaver
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        self.ignoresMouseEvents = false
        self.sharingType = .none      // invisible to screen recording
        self.hidesOnDeactivate = false
        self.isMovable = false

        let content = NotchView(
            request: request,
            onAction: { [weak self] action in self?.finish(action: action, dismissed: false) },
            onDismiss: { [weak self] in self?.finish(action: nil, dismissed: true) }
        )
        self.contentView = NSHostingView(rootView: content)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func show() {
        self.alphaValue = 0
        self.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            self.animator().alphaValue = 1
        }
        if let t = request.timeout, t > 0 {
            dismissTimer = Timer.scheduledTimer(withTimeInterval: t, repeats: false) { [weak self] _ in
                self?.finish(action: nil, dismissed: true)
            }
        }
    }

    func dismissImmediately() { finish(action: nil, dismissed: true) }

    private func finish(action: String?, dismissed: Bool) {
        guard !didComplete else { return }
        didComplete = true
        dismissTimer?.invalidate()
        let response = NotifyResponse(action: action, dismissed: dismissed)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            self.animator().alphaValue = 0
        }, completionHandler: {
            self.orderOut(nil)
            self.completion(response)
        })
    }
}

// MARK: - SwiftUI card

struct NotchView: View {
    let request: NotifyRequest
    let onAction: (String) -> Void
    let onDismiss: () -> Void

    private var hasNotch: Bool {
        (NSScreen.main?.safeAreaInsets.top ?? 0) > 0
    }

    private var accentColor: Color {
        if let hex = request.accentHex, let c = Color(hex: hex) { return c }
        return .accentColor
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top gutter; on notched Macs we push the card below the notch.
            Color.clear.frame(height: hasNotch ? 34 : 6)

            HStack(alignment: .top, spacing: 12) {
                // LEFT: image / icon
                ImageThumb(image: request.image, accent: accentColor)
                    .frame(width: 44, height: 44)

                // CENTER: title + subtitle + body
                VStack(alignment: .leading, spacing: 4) {
                    Text(request.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    if let sub = request.subtitle, !sub.isEmpty {
                        Text(sub)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(.white.opacity(0.65))
                            .lineLimit(1)
                    }

                    if let body = request.body, !body.isEmpty {
                        Text(body)
                            .font(.system(size: 12.5))
                            .foregroundStyle(.white.opacity(0.88))
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 2)
                    }

                    if !request.actions.isEmpty {
                        HStack(spacing: 8) {
                            ForEach(Array(request.actions.enumerated()), id: \.offset) { idx, action in
                                ActionButton(
                                    label: action,
                                    isPrimary: idx == 0,
                                    accent: accentColor
                                ) {
                                    onAction(action)
                                }
                                .keyboardShortcut(idx == 0 ? .return : (idx == 1 ? .cancelAction : .defaultAction))
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.top, 8)
                    }
                }

                // RIGHT: close
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(6)
                        .background(Circle().fill(.white.opacity(0.1)))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
            }
            .padding(14)
            .background(
                ZStack {
                    VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.black.opacity(request.style == "solid" ? 0.55 : 0.28))
                }
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(.white.opacity(0.09), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.4), radius: 22, x: 0, y: 10)
            .padding(.horizontal, 10)
        }
    }
}

// MARK: - Image thumbnail
// Accepts:
//   - "sf:symbol.name"           -> SF Symbol
//   - any file path / file URL    -> loads as NSImage
//   - nil / failure               -> falls back to a glyph

struct ImageThumb: View {
    let image: String?
    let accent: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(.white.opacity(0.06), lineWidth: 0.5)
                )

            if let raw = image {
                if raw.hasPrefix("sf:") {
                    let symbol = String(raw.dropFirst(3))
                    Image(systemName: symbol)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(accent)
                } else if let ns = loadImage(from: raw) {
                    Image(nsImage: ns)
                        .resizable()
                        .scaledToFill()
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else {
                    fallback
                }
            } else {
                fallback
            }
        }
    }

    private var fallback: some View {
        Image(systemName: "sparkles")
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(accent)
    }

    private func loadImage(from raw: String) -> NSImage? {
        let expanded = (raw as NSString).expandingTildeInPath
        if FileManager.default.fileExists(atPath: expanded) {
            return NSImage(contentsOfFile: expanded)
        }
        if let url = URL(string: raw), url.isFileURL {
            return NSImage(contentsOf: url)
        }
        return nil
    }
}

// MARK: - Action button

struct ActionButton: View {
    let label: String
    let isPrimary: Bool
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isPrimary ? accent.opacity(0.85) : Color.white.opacity(0.12))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(.white.opacity(isPrimary ? 0.18 : 0.08), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Helpers

struct VisualEffectBlur: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blendingMode
        v.state = .active
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

extension Color {
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt64(s, radix: 16) else { return nil }
        let r = Double((v >> 16) & 0xFF) / 255.0
        let g = Double((v >> 8) & 0xFF) / 255.0
        let b = Double(v & 0xFF) / 255.0
        self = Color(red: r, green: g, blue: b)
    }
}
