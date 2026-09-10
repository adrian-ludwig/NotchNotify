import Foundation

/// The rectangle of the notification panel that should receive mouse events.
/// The panel is a fixed-size canvas so animations have room; only the live
/// SwiftUI content (anchored top-center) is interactive. Everything else must
/// pass clicks through to whatever sits beneath the panel.
enum ContentHitRegion {
    /// - Parameter flipped: true when the view's origin is top-left (`NSHostingView` is flipped),
    ///   false for the default AppKit bottom-left origin.
    /// Returns nil when the content size is not yet known.
    static func rect(bounds: CGRect, contentSize: CGSize, flipped: Bool) -> CGRect? {
        guard contentSize.width > 1, contentSize.height > 1 else { return nil }
        let w = min(contentSize.width, bounds.width)
        let h = min(contentSize.height, bounds.height)
        let y = flipped ? bounds.minY : bounds.maxY - h
        return CGRect(x: bounds.minX + (bounds.width - w) / 2, y: y, width: w, height: h)
    }

    static func contains(_ point: CGPoint, bounds: CGRect, contentSize: CGSize, flipped: Bool) -> Bool {
        rect(bounds: bounds, contentSize: contentSize, flipped: flipped)?.contains(point) ?? false
    }
}
