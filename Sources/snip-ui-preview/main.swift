import AppKit
import SnipUI

// snip-ui-preview: draws Snip's own UI off-screen at interface sizes and saves PNGs, to check how
// it looks without recording. Nothing appears on screen and no settings change.
//
// usage: snip-ui-preview [folder] [percent ...] [video.mp4]
//   folder defaults to ./snip-ui-preview, the sizes to 100 and 200. The video is the recording the
//   after-recording panel ("done-panel") shows; without one, a short sample is made. Prints each PNG's path.

MainActor.assumeIsolated {
    let arguments = Array(CommandLine.arguments.dropFirst())
    let folder = URL(fileURLWithPath: arguments.first ?? "snip-ui-preview", isDirectory: true)
    let rest = arguments.dropFirst()
    let percents = rest.compactMap(Double.init)
    let video = rest.first { ["mp4", "mov"].contains(URL(fileURLWithPath: $0).pathExtension.lowercased()) }
        .map { URL(fileURLWithPath: $0) }
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    do {
        let scales = (percents.isEmpty ? [100, 200] : percents).map { $0 / 100 }
        for url in try UIPreviews.write(scales: scales, to: folder, video: video) {
            print(url.path)
        }
    } catch {
        FileHandle.standardError.write(Data("snip-ui-preview: \(error)\n".utf8))
        exit(1)
    }
}
