import CoreGraphics

public enum DisplayGeometry {
    /// SwiftUI dividers can leave a half-point remainder. At 2× that becomes an
    /// odd pixel dimension, which GNOME cannot divide into a 200% logical size.
    /// Align the actual view, not just the requested mode, to avoid stretching
    /// the guest framebuffer over a differently sized native view.
    public static func alignedViewSize(_ available: CGSize) -> CGSize {
        CGSize(width: max(0, available.width.rounded(.down)),
               height: max(0, available.height.rounded(.down)))
    }
}
