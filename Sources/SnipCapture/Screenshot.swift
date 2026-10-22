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
        let content = try await ShareableContent.fetch(onScreenWindowsOnly: false)
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
            let clipped = rect.standardized.intersection(bounds)
            guard !clipped.isNull, clipped.width * scale >= 1, clipped.height * scale >= 1 else {
                throw SnipCaptureError.regionOutsideDisplay(rect)
            }
            // Whole device pixels, mapped 1:1, so text stays sharp.
            let x0 = (clipped.minX * scale).rounded(), y0 = (clipped.minY * scale).rounded()
            let x1 = max((clipped.maxX * scale).rounded(), x0 + 1), y1 = max((clipped.maxY * scale).rounded(), y0 + 1)
            configuration.sourceRect = CGRect(x: x0 / scale, y: y0 / scale, width: (x1 - x0) / scale, height: (y1 - y0) / scale)
            configuration.width = Int(x1 - x0)
            configuration.height = Int(y1 - y0)
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

    private static func pixels(_ value: CGFloat) -> Int {
        max(1, Int(value.rounded()))
    }
}
