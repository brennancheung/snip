import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation
import ScreenCaptureKit
import SnipCore

/// The filter and stream configuration for one `CaptureTarget`.
struct CapturePlan {
    let filter: SCContentFilter
    let configuration: SCStreamConfiguration
    /// Output size in pixels, always even (yuv420p needs that).
    let pixelSize: CGSize

    static func make(target: CaptureTarget, settings: RecordingSettings, content: SCShareableContent) throws -> CapturePlan {
        let configuration = baseConfiguration(settings: settings)
        let filter: SCContentFilter
        let pointSize: CGSize
        let scale: CGFloat

        switch target {
        case .window(let windowID):
            guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
                throw SnipCaptureError.windowNotFound(windowID)
            }
            // Desktop-independent: the window is followed as it moves, and nothing covering it shows.
            filter = SCContentFilter(desktopIndependentWindow: window)
            pointSize = filter.contentRect.isEmpty ? window.frame.size : filter.contentRect.size
            scale = pixelScale(of: filter, fallbackDisplay: Displays.displayID(holding: window.frame))
            // If the window is resized while recording, fit it into the frame rather than crop it.
            configuration.scalesToFit = true

        case .display(let displayID):
            let display = try findDisplay(displayID, in: content)
            filter = displayFilter(display, content: content)
            pointSize = CGSize(width: display.width, height: display.height)
            scale = pixelScale(of: filter, fallbackDisplay: displayID)

        case .region(let displayID, let rect):
            let display = try findDisplay(displayID, in: content)
            filter = displayFilter(display, content: content)
            scale = pixelScale(of: filter, fallbackDisplay: displayID)
            let bounds = CGRect(x: 0, y: 0, width: display.width, height: display.height)
            let clipped = rect.standardized.intersection(bounds)
            guard !clipped.isNull, clipped.width * scale >= 4, clipped.height * scale >= 4 else {
                throw SnipCaptureError.regionOutsideDisplay(rect)
            }
            let factor = scale * settings.scale.factor
            let width = evenPixels(clipped.width * factor)
            let height = evenPixels(clipped.height * factor)
            // Snap the source to whole device pixels, sized so it maps 1:1 (or 2:1 at half scale)
            // onto the even output size: no resampling blur on text.
            let sourceWidth = CGFloat(width) / factor
            let sourceHeight = CGFloat(height) / factor
            let x = min((clipped.minX * scale).rounded() / scale, bounds.maxX - sourceWidth)
            let y = min((clipped.minY * scale).rounded() / scale, bounds.maxY - sourceHeight)
            configuration.sourceRect = CGRect(x: max(0, x), y: max(0, y), width: sourceWidth, height: sourceHeight)
            configuration.width = width
            configuration.height = height
            return CapturePlan(filter: filter, configuration: configuration, pixelSize: CGSize(width: width, height: height))
        }

        let factor = scale * settings.scale.factor
        configuration.width = evenPixels(pointSize.width * factor)
        configuration.height = evenPixels(pointSize.height * factor)
        return CapturePlan(
            filter: filter,
            configuration: configuration,
            pixelSize: CGSize(width: configuration.width, height: configuration.height)
        )
    }

    private static func baseConfiguration(settings: RecordingSettings) -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        let fps = min(max(settings.fps, 1), 120)
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))
        configuration.showsCursor = settings.showCursor
        configuration.queueDepth = 6
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        // Displays are usually P3; sRGB is what players and Slack assume, and what ffmpeg tags.
        configuration.colorSpaceName = CGColorSpace.sRGB
        configuration.capturesAudio = settings.recordSystemAudio
        if settings.recordSystemAudio {
            // Only in Snip.app. From a terminal (snip-cli) the terminal counts as this process, so it
            // would also drop the audio of everything started there (afplay, say). Snip's own sounds
            // are left out by the display filter anyway, and a window recording only hears its app.
            configuration.excludesCurrentProcessAudio = Bundle.main.bundleURL.pathExtension == "app"
            configuration.sampleRate = 48_000
            configuration.channelCount = 2
        }
        // The microphone is recorded by MicrophoneSpans instead, so it can go on and off mid-recording.
        configuration.captureMicrophone = false
        return configuration
    }

    private static func findDisplay(_ displayID: CGDirectDisplayID, in content: SCShareableContent) throws -> SCDisplay {
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw SnipCaptureError.displayNotFound(displayID)
        }
        return display
    }

    /// The whole display minus Snip's own windows (the recording pill and red border must not be in the video).
    private static func displayFilter(_ display: SCDisplay, content: SCShareableContent) -> SCContentFilter {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let ownApps = content.applications.filter { $0.processID == ownPID }
        if !ownApps.isEmpty {
            // Excluding the application covers windows it opens after the stream starts, too.
            return SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
        }
        let ownWindows = content.windows.filter { $0.owningApplication?.processID == ownPID }
        return SCContentFilter(display: display, excludingWindows: ownWindows)
    }

    private static func pixelScale(of filter: SCContentFilter, fallbackDisplay: CGDirectDisplayID?) -> CGFloat {
        let scale = CGFloat(filter.pointPixelScale)
        if scale > 0 { return scale }
        return fallbackDisplay.map(Displays.backingScale(of:)) ?? 2
    }
}

/// Rounds down to an even pixel count, at least 2.
func evenPixels(_ value: CGFloat) -> Int {
    max(2, Int(value.rounded(.down)) & ~1)
}

extension RecordingSettings.Scale {
    /// Multiplier on native pixels.
    var factor: CGFloat {
        switch self {
        case .full: return 1
        case .half: return 0.5
        }
    }
}
