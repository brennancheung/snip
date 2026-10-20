import AVFoundation
import Foundation

/// For keeping the uncompressed movie when ffmpeg is missing or fails. System audio is always
/// captured; when it was turned off for part of the recording, ffmpeg would have muted that, so
/// without ffmpeg the movie keeps its video only.
public enum MovieAudio {
    /// Rewrites the movie at `url` with its video tracks only (passthrough, no re-encode).
    public static func removeAudio(from url: URL) async throws {
        let asset = AVURLAsset(url: url)
        let composition = AVMutableComposition()
        for track in try await asset.loadTracks(withMediaType: .video) {
            let range = try await track.load(.timeRange)
            let copy = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
            try copy?.insertTimeRange(range, of: track, at: range.start)
        }
        guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
            throw SnipCaptureError.recordingFailed("the system audio couldn't be removed")
        }
        let videoOnly = url.deletingPathExtension().appendingPathExtension("video.mov")
        try? FileManager.default.removeItem(at: videoOnly)
        try await export.export(to: videoOnly, as: .mov)
        _ = try FileManager.default.replaceItemAt(url, withItemAt: videoOnly)
    }
}
