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
        signal(SIGPIPE, SIG_IGN)

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
        let pathCapacity = MemoryLayout.size(ofValue: addr.sun_path)
        _ = path.withCString { src in
            withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
                ptr.withMemoryRebound(to: CChar.self, capacity: pathCapacity) { dst in
                    strncpy(dst, src, pathCapacity - 1)
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

// MARK: - Queue style

enum QueueStyle: String {
    case none, bar, badge, both

    static func fromEnv() -> QueueStyle {
        let raw = ProcessInfo.processInfo.environment["NOTCH_QUEUE_STYLE"]?.lowercased() ?? ""
        return QueueStyle(rawValue: raw) ?? .both
    }

    var showBar: Bool { self == .bar || self == .both }
    var showBadge: Bool { self == .badge || self == .both }
}

// MARK: - Notch mode

enum NotchMode: String {
    case auto, on, off

    static func fromEnv() -> NotchMode {
        let raw = ProcessInfo.processInfo.environment["NOTCH_FORCE"]?.lowercased() ?? ""
        return NotchMode(rawValue: raw) ?? .auto
    }

    // Physical notch geometry on Apple Silicon MacBook Pros (14"/16").
    // auxiliaryTopLeftArea/auxiliaryTopRightArea describe the *menu bar* halves,
    // not the notch — they include ~20pt of padding each side and the full 38pt
    // menu bar height. Use hardcoded notch dimensions instead.
    static let defaultWidth: CGFloat = 180
    static let defaultHeight: CGFloat = 32

    static var notchWidth: CGFloat {
        if let raw = ProcessInfo.processInfo.environment["NOTCH_WIDTH"],
           let v = Double(raw) { return CGFloat(v) }
        return defaultWidth
    }

    static var notchHeight: CGFloat {
        if let raw = ProcessInfo.processInfo.environment["NOTCH_HEIGHT"],
           let v = Double(raw) { return CGFloat(v) }
        return defaultHeight
    }
}

enum NotchScreen {
    private static let targetMode = ScreenTargetMode.fromEnv()

    static var target: NSScreen {
        let screens = NSScreen.screens
        let candidates = screens.map { screen in
            NotchScreenSelector.ScreenCandidate(
                isMain: screen == NSScreen.main,
                hasNotch: screen.safeAreaInsets.top > 0
            )
        }

        guard let targetIndex = NotchScreenSelector.targetIndex(in: candidates, mode: targetMode) else {
            fatalError("Expected at least one available screen")
        }

        return screens[targetIndex]
    }

    static var anyHasNotch: Bool {
        NSScreen.screens.contains(where: { $0.safeAreaInsets.top > 0 })
    }
}

// MARK: - Presenter

final class NotchPresenter {
    private var currentWindow: NotchWindow?
    private struct Pending {
        let request: NotifyRequest
        let completion: (NotifyResponse) -> Void
    }
    private var queue: [Pending] = []
    private let queueStyle: QueueStyle = QueueStyle.fromEnv()
    private let notchMode: NotchMode = NotchMode.fromEnv()

    func present(_ request: NotifyRequest, completion: @escaping (NotifyResponse) -> Void) {
        if let window = currentWindow {
            queue.append(Pending(request: request, completion: completion))
            window.updateQueueDepth(queue.count)
            return
        }
        showNow(request: request, completion: completion)
    }

    private func showNow(request: NotifyRequest, completion: @escaping (NotifyResponse) -> Void) {
        let window = NotchWindow(
            request: request,
            queueStyle: queueStyle,
            notchMode: notchMode,
            initialQueueDepth: queue.count
        ) { [weak self] response in
            completion(response)
            guard let self else { return }
            self.currentWindow = nil
            if !self.queue.isEmpty {
                let next = self.queue.removeFirst()
                self.showNow(request: next.request, completion: next.completion)
            }
        }
        currentWindow = window
        window.show()
    }
}

// MARK: - Notch window
// Borderless, transparent, floating panel pinned to top-center of the main screen.
// Critical: sharingType = .none makes this invisible to screen recording.

final class NotchAnim: ObservableObject {
    @Published var capsuleExpanded = false
    @Published var cardShown = false
    @Published var queueVisible = false
    @Published var queueDepth: Int = 0
}

final class NotchWindow: NSPanel {
    private let request: NotifyRequest
    private let completion: (NotifyResponse) -> Void
    private let queueStyle: QueueStyle
    private let notchMode: NotchMode
    private let targetScreenHasNotch: Bool
    private var didComplete = false
    private var dismissTimer: Timer?
    private let anim = NotchAnim()

    init(
        request: NotifyRequest,
        queueStyle: QueueStyle,
        notchMode: NotchMode,
        initialQueueDepth: Int,
        completion: @escaping (NotifyResponse) -> Void
    ) {
        self.request = request
        self.queueStyle = queueStyle
        self.notchMode = notchMode
        self.completion = completion
        self.anim.queueDepth = initialQueueDepth

        let screen = NotchScreen.target
        self.targetScreenHasNotch = screen.safeAreaInsets.top > 0
        let size = NSSize(width: 520, height: 320)
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
        self.sharingType = .none
        self.hidesOnDeactivate = false
        self.isMovable = false
        self.becomesKeyOnlyIfNeeded = true

        let content = NotchView(
            request: request,
            anim: anim,
            queueStyle: queueStyle,
            notchMode: notchMode,
            targetScreenHasNotch: targetScreenHasNotch,
            onAction: { [weak self] action in self?.finish(action: action, dismissed: false) },
            onDismiss: { [weak self] in self?.finish(action: nil, dismissed: true) }
        )
        let hostingView = NSHostingView(rootView: content)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = .clear
        self.contentView = hostingView
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    private var effectiveHasNotch: Bool {
        EffectiveNotchMode.resolve(notchMode: notchMode, targetScreenHasNotch: targetScreenHasNotch)
    }

    func show() {
        self.alphaValue = 1
        self.orderFrontRegardless()

        if effectiveHasNotch {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
                anim.capsuleExpanded = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
                guard let self, !self.didComplete else { return }
                withAnimation(.spring(response: 0.42, dampingFraction: 0.85)) {
                    self.anim.cardShown = true
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { [weak self] in
                guard let self, !self.didComplete else { return }
                withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                    self.anim.queueVisible = true
                }
            }
        } else {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.85)) {
                anim.cardShown = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) { [weak self] in
                guard let self, !self.didComplete else { return }
                withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                    self.anim.queueVisible = true
                }
            }
        }

        if let t = request.timeout, t > 0 {
            dismissTimer = Timer.scheduledTimer(withTimeInterval: t, repeats: false) { [weak self] _ in
                self?.finish(action: nil, dismissed: true)
            }
        }
    }

    func dismissImmediately() { finish(action: nil, dismissed: true) }

    func updateQueueDepth(_ depth: Int) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                self.anim.queueDepth = depth
            }
        }
    }

    private func finish(action: String?, dismissed: Bool) {
        guard !didComplete else { return }
        didComplete = true
        dismissTimer?.invalidate()
        let response = NotifyResponse(action: action, dismissed: dismissed)

        withAnimation(.easeIn(duration: 0.08)) {
            anim.queueVisible = false
        }
        withAnimation(.easeIn(duration: 0.18)) {
            anim.cardShown = false
        }

        if effectiveHasNotch {
            // Card retracts fast, then capsule contracts.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
                    self?.anim.capsuleExpanded = false
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.36) { [weak self] in
                guard let self else { return }
                self.orderOut(nil)
                self.completion(response)
            }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                guard let self else { return }
                self.orderOut(nil)
                self.completion(response)
            }
        }
    }
}

// MARK: - SwiftUI card

struct NotchView: View {
    let request: NotifyRequest
    @ObservedObject var anim: NotchAnim
    let queueStyle: QueueStyle
    let notchMode: NotchMode
    let targetScreenHasNotch: Bool
    let onAction: (String) -> Void
    let onDismiss: () -> Void

    private var hasRealNotch: Bool {
        EffectiveNotchMode.resolve(notchMode: notchMode, targetScreenHasNotch: targetScreenHasNotch)
    }

    private var notchHeight: CGFloat {
        hasRealNotch ? NotchMode.notchHeight : 4
    }

    private var notchWidth: CGFloat {
        hasRealNotch ? NotchMode.notchWidth : 80
    }

    private var accentColor: Color {
        if let hex = request.accentHex, let c = Color(hex: hex) { return c }
        return .accentColor
    }

    private let cardWidth: CGFloat = 460
    private let cardCornerRadius: CGFloat = 24
    private let capsuleOverlap: CGFloat = 8
    private let popoverTopInset: CGFloat = 72

    private var shouldShowBadge: Bool {
        hasRealNotch && queueStyle.showBadge && anim.queueDepth > 0 && anim.queueVisible
    }

    private var shouldShowBar: Bool {
        queueStyle.showBar && anim.queueDepth > 0 && anim.queueVisible
    }

    var body: some View {
        Group {
            if hasRealNotch {
                notchLayout
            } else {
                popoverLayout
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var notchLayout: some View {
        ZStack(alignment: .top) {
            if anim.cardShown {
                VStack(spacing: QueueBarStyle.stackSpacing) {
                    card
                        .frame(width: cardWidth)
                    if shouldShowBar {
                        QueueBar(count: anim.queueDepth)
                            .frame(width: cardWidth)
                            .transition(.opacity.combined(with: .offset(y: -10)))
                    }
                }
                .offset(y: notchHeight - capsuleOverlap)
                .transition(.asymmetric(
                    insertion: .offset(y: -notchHeight).combined(with: .opacity),
                    removal: .offset(y: -notchHeight).combined(with: .opacity)
                ))
            }

            NotchCapsule(
                width: anim.capsuleExpanded ? cardWidth : notchWidth,
                height: notchHeight,
                hasNotch: true
            )
            .overlay(alignment: .trailing) {
                if shouldShowBadge {
                    QueueBadge(count: anim.queueDepth)
                        .offset(x: -12, y: -1)
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.38, dampingFraction: 0.82), value: anim.capsuleExpanded)
            .animation(.spring(response: 0.32, dampingFraction: 0.78), value: anim.queueDepth)
        }
    }

    private var popoverLayout: some View {
        VStack(spacing: QueueBarStyle.stackSpacing) {
            if anim.cardShown {
                card
                    .frame(width: cardWidth)
                    .transition(.asymmetric(
                        insertion: .offset(y: -40).combined(with: .opacity),
                        removal: .offset(y: -20).combined(with: .opacity)
                    ))
            }
            if shouldShowBar {
                QueueBar(count: anim.queueDepth)
                    .frame(width: cardWidth)
                    .transition(.opacity.combined(with: .offset(y: -10)))
            }
        }
        .padding(.top, popoverTopInset)
    }

    private var card: some View {
        HStack(alignment: .top, spacing: 12) {
            ImageThumb(image: request.image, accent: accentColor)
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 4) {
                Text(request.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if let sub = request.subtitle, !sub.isEmpty {
                    Text(sub)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if let body = request.body, !body.isEmpty {
                    Text(body)
                        .font(.system(size: 12.5))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }

                if !request.actions.isEmpty {
                    ActionsRow(actions: request.actions, accent: accentColor, onAction: onAction)
                        .padding(.top, 8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .padding(4)
            }
            .buttonStyle(.glass)
            .clipShape(Circle())
            .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(16)
        .glassEffect(.regular, in: UnevenRoundedRectangle(
            topLeadingRadius: hasRealNotch ? 0 : cardCornerRadius,
            bottomLeadingRadius: cardCornerRadius,
            bottomTrailingRadius: cardCornerRadius,
            topTrailingRadius: hasRealNotch ? 0 : cardCornerRadius,
            style: .continuous
        ))
        .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 8)
    }
}

// On notched displays: black bar with flat top + rounded bottom that
// visually extends the real notch. On non-notched displays: thin pill
// line at the top that widens into the card width.
struct NotchCapsule: View {
    let width: CGFloat
    let height: CGFloat
    let hasNotch: Bool

    var body: some View {
        if hasNotch {
            NotchCapsuleShape(bottomRadius: min(height * 0.45, 12))
                .fill(Color.black)
                .frame(width: width, height: height)
        } else {
            Capsule()
                .fill(Color.black.opacity(0.9))
                .frame(width: width, height: height)
                .padding(.top, 4)
        }
    }
}

struct NotchCapsuleShape: Shape {
    var bottomRadius: CGFloat

    var animatableData: CGFloat {
        get { bottomRadius }
        set { bottomRadius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let r = min(bottomRadius, rect.height, rect.width / 2)
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.maxY),
                       control: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - r),
                       control: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

// MARK: - Queue indicators

struct QueueBadge: View {
    let count: Int

    var body: some View {
        Text(count > 99 ? "99+" : "\(count)")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.black)
            .frame(minWidth: 18, minHeight: 18)
            .padding(.horizontal, 5)
            .background(Circle().fill(Color.white))
            .shadow(color: .black.opacity(0.35), radius: 2, x: 0, y: 1)
    }
}

struct QueueBar: View {
    let count: Int

    var body: some View {
        GlassEffectContainer {
            HStack(spacing: 8) {
                Image(systemName: "square.stack.3d.down.forward.fill")
                    .font(.system(size: 11, weight: .semibold))
                Text(count == 1 ? "1 more notification" : "\(count) more notifications")
                    .font(.system(size: 12, weight: .medium))
                Spacer(minLength: 0)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, QueueBarStyle.horizontalPadding)
            .padding(.vertical, QueueBarStyle.verticalPadding)
            .glassEffect(.regular, in: Capsule(style: .continuous))
            .shadow(color: .black.opacity(0.2), radius: QueueBarStyle.shadowRadius, x: 0, y: QueueBarStyle.shadowYOffset)
        }
    }
}

// MARK: - Actions row

private struct ActionsRow: View {
    let actions: [String]
    let accent: Color
    let onAction: (String) -> Void

    @ViewBuilder
    private func button(idx: Int, action: String) -> some View {
        let btn = ActionButton(label: action, isPrimary: idx == 0, accent: accent) { onAction(action) }
        if idx == 0 {
            btn.keyboardShortcut(.return)
        } else if idx == 1 {
            btn.keyboardShortcut(.cancelAction)
        } else {
            btn
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(actions.enumerated()), id: \.offset) { idx, action in
                button(idx: idx, action: action)
            }
            Spacer(minLength: 0)
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
            Color.clear
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 13, style: .continuous))

            if let raw = image {
                if raw.hasPrefix("sf:") {
                    let symbol = String(raw.dropFirst(3))
                    Image(systemName: symbol)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(accent)
                } else if raw.hasPrefix("http://") || raw.hasPrefix("https://"),
                          let url = URL(string: raw) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img):
                            img.resizable().scaledToFill()
                                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                        default:
                            fallback
                        }
                    }
                } else if let ns = loadImage(from: raw) {
                    Image(nsImage: ns)
                        .resizable()
                        .scaledToFill()
                        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                } else if isEmoji(raw) {
                    Text(raw).font(.system(size: 26))
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

    private func isEmoji(_ s: String) -> Bool {
        guard !s.isEmpty else { return false }
        return s.unicodeScalars.first.map {
            $0.properties.isEmoji && $0.value > 127
        } ?? false
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
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isPrimary ? .white : .primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .frame(minWidth: 44)
                .background {
                    if isPrimary {
                        Capsule(style: .continuous).fill(accent)
                    } else {
                        Color.clear
                            .glassEffect(.regular, in: Capsule(style: .continuous))
                    }
                }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Helpers

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
