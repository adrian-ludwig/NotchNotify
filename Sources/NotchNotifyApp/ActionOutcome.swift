import Foundation

/// What a finished notification reports back and whether it opens the request's URL.
enum ActionOutcome {
    static func response(action: String?, dismissed: Bool, at date: Date) -> NotifyResponse {
        guard let action, !dismissed else { return NotifyResponse(action: nil, dismissed: true) }
        return NotifyResponse(
            action: action,
            dismissed: false,
            clickedAt: ISO8601DateFormatter().string(from: date)
        )
    }

    /// The URL to open: only when the clicked action is the first one and the request carries a valid http(s) url.
    static func urlToOpen(for request: NotifyRequest, action: String?) -> URL? {
        guard let action, action == request.actions.first, let url = request.url else { return nil }
        return OpenURL.parse(url)
    }
}
