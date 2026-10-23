import CoreGraphics
import CoreVideo
import Foundation
import ImageIO
import ScreenCaptureKit
import SnipCore
import UniformTypeIdentifiers

/// A still picture of a window, a region or a display, at the display's native pixels, without
/// the cursor or Snip's own windows.
public enum Screenshot {
    public struct Picture: @unchecked Sendable {
        public let image: CGImage
        /// Pixels per point (2 on Retina), so the PNG opens at the size it was on screen.
        public let scale: CGFloat
    }

    public static func capture(_ target: CaptureTarget) async throws -> Picture {
        try await capture(target, in: ShareableContent.fetch(onScreenWindowsOnly: false))
    }

    /// Every display as it is now, for an area screenshot taken from a frozen screen: the box is
    /// drawn over these pictures and cut from them, so the app underneath never sees the pointer
    /// move and keeps its hover state. A display that fails is left out, and is captured live.
    public static func freeze() async -> [CGDirectDisplayID: Picture] {
        guard let content = try? await ShareableContent.fetch(onScreenWindowsOnly: false) else { return [:] }
        var pictures: [CGDirectDisplayID: Picture] = [:]
        for display in content.displays {
            pictures[display.displayID] = try? await capture(.display(displayID: display.displayID), in: content)
        }
        return pictures
    }

    /// The part of a display's picture inside `rect` (display-relative points, top-left origin),
    /// on the same whole device pixels a live capture of that region takes.
    public static func crop(_ picture: Picture, to rect: CGRect) throws -> Picture {
        let scale = picture.scale
        let bounds = CGRect(x: 0, y: 0, width: CGFloat(picture.image.width) / scale, height: CGFloat(picture.image.height) / scale)
        let pixels = try devicePixels(of: rect, within: bounds, scale: scale)
        guard let image = picture.image.cropping(to: pixels) else {
            throw SnipCaptureError.captureFailed("Couldn't cut the area from the frozen screen.")
        }
        return Picture(image: image, scale: scale)
    }

    private static func capture(_ target: CaptureTarget, in content: SCShareableContent) async throws -> Picture {
        let configuration = SCStreamConfiguration()
        configuration.showsCursor = false
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        // Displays are usually P3; sRGB is what browsers and Slack assume, as for recordings.
        configuration.colorSpaceName = CGColorSpace.sRGB
        let filter: SCContentFilter
        let scale: CGFloat

        switch target {
        case .window(let windowID):
            guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
                throw SnipCaptureError.windowNotFound(windowID)
            }
            filter = SCContentFilter(desktopIndependentWindow: window)
            scale = CapturePlan.pixelScale(of: filter, fallbackDisplay: Displays.displayID(holding: window.frame))
            let size = filter.contentRect.isEmpty ? window.frame.size : filter.contentRect.size
            configuration.width = pixels(size.width * scale)
            configuration.height = pixels(size.height * scale)
            // The window alone: rounded corners transparent, no shadow.
            configuration.backgroundColor = .clear
            configuration.ignoreShadowsSingleWindow = true

        case .display(let displayID):
            let display = try CapturePlan.findDisplay(displayID, in: content)
            filter = CapturePlan.displayFilter(display, content: content)
            scale = CapturePlan.pixelScale(of: filter, fallbackDisplay: displayID)
            configuration.width = pixels(CGFloat(display.width) * scale)
            configuration.height = pixels(CGFloat(display.height) * scale)

        case .region(let displayID, let rect):
            let display = try CapturePlan.findDisplay(displayID, in: content)
            filter = CapturePlan.displayFilter(display, content: content)
            scale = CapturePlan.pixelScale(of: filter, fallbackDisplay: displayID)
            let bounds = CGRect(x: 0, y: 0, width: display.width, height: display.height)
            let pixels = try devicePixels(of: rect, within: bounds, scale: scale)
            configuration.sourceRect = CGRect(x: pixels.minX / scale, y: pixels.minY / scale, width: pixels.width / scale, height: pixels.height / scale)
            configuration.width = Int(pixels.width)
            configuration.height = Int(pixels.height)
        }

        do {
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            return Picture(image: image, scale: scale)
        } catch {
            throw SnipCaptureError.from(error)
        }
    }

    /// Writes `picture` to `url` as a PNG, its resolution set so it opens at its on-screen size.
    public static func writePNG(_ picture: Picture, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw SnipCaptureError.captureFailed("Couldn't create \(url.lastPathComponent).")
        }
        let dpi = 72 * picture.scale
        let properties = [kCGImagePropertyDPIWidth: dpi, kCGImagePropertyDPIHeight: dpi] as CFDictionary
        CGImageDestinationAddImage(destination, picture.image, properties)
        guard CGImageDestinationFinalize(destination) else {
            throw SnipCaptureError.captureFailed("Couldn't write \(url.lastPathComponent).")
        }
    }

    /// `rect` clipped to `bounds` (points) and snapped to whole device pixels, at least one, so
    /// it maps 1:1 and text stays sharp. In pixels, top-left origin.
    private static func devicePixels(of rect: CGRect, within bounds: CGRect, scale: CGFloat) throws -> CGRect {
        let clipped = rect.standardized.intersection(bounds)
        guard !clipped.isNull, clipped.width * scale >= 1, clipped.height * scale >= 1 else {
            throw SnipCaptureError.regionOutsideDisplay(rect)
        }
        let x0 = (clipped.minX * scale).rounded(), y0 = (clipped.minY * scale).rounded()
        let x1 = max((clipped.maxX * scale).rounded(), x0 + 1), y1 = max((clipped.maxY * scale).rounded(), y0 + 1)
        return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }

    private static func pixels(_ value: CGFloat) -> Int {
        max(1, Int(value.rounded()))
    }
}
