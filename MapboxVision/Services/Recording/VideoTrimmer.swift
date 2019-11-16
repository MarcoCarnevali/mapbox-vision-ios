import AVFoundation
import Foundation

private let timeScale: CMTimeScale = 600
private let fileType: AVFileType = .mp4

enum VideoTrimmerError: LocalizedError {
    case notSuitableSource
    case incorrectConfiguration
}

final class VideoTrimmer {
    typealias TrimCompletion = (Error?) -> Void

    func trimVideo(source: String, clip: VideoClip, completion: @escaping TrimCompletion) {
        let sourceURL = URL(fileURLWithPath: source)
        let options = [
            AVURLAssetPreferPreciseDurationAndTimingKey: true,
        ]

        let asset = AVURLAsset(url: sourceURL, options: options)
        guard
            asset.isExportable,
            let videoAssetTrack = asset.tracks(withMediaType: .video).first
        else {
            assertionFailure("Source asset is not exportable or doesn't contain a video track. Asset: \(asset).")
            completion(VideoTrimmerError.notSuitableSource)
            return
        }

        let composition = AVMutableComposition()
        guard
            let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: CMPersistentTrackID())
        else {
            assertionFailure("Unable to add video track to composition \(composition).")
            completion(VideoTrimmerError.incorrectConfiguration)
            return
        }

        let startTime = CMTime(seconds: Double(clip.startTime), preferredTimescale: timeScale)
        let endTime = CMTime(seconds: Double(clip.stopTime), preferredTimescale: timeScale)

        let durationOfCurrentSlice = CMTimeSubtract(endTime, startTime)
        let timeRangeForCurrentSlice = CMTimeRangeMake(start: startTime, duration: durationOfCurrentSlice)

        do {
            try videoTrack.insertTimeRange(timeRangeForCurrentSlice, of: videoAssetTrack, at: CMTime())
        } catch {
            completion(error)
            return
        }

        guard
            let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough)
        else {
            assertionFailure("Unable to create an export session with composition \(composition).")
            completion(VideoTrimmerError.incorrectConfiguration)
            return
        }

        exportSession.outputURL = URL(fileURLWithPath: clip.path)
        exportSession.outputFileType = fileType
        exportSession.shouldOptimizeForNetworkUse = true

        exportSession.exportAsynchronously {
            completion(exportSession.error)
        }
    }
}
