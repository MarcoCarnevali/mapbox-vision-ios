//
//  RecordedVideoSampler.swift
//  MapboxVision
//
//  Created by Avi Cieplinski on 2/14/19.
//  Copyright © 2019 Mapbox. All rights reserved.
//

import UIKit
import AVFoundation
import ModelIO

class RecordedVideoSampler: NSObject, Streamable {

    typealias Handler = (CMSampleBuffer) -> Void

    let iPhoneXBackFacingCameraFoV: Float = Float(65.576)
    let iPhoneXBackFacingCameraFocalLength: Float = Float(23.551327)

    var assetPath: String?
    var assetFrameRate: Float = 60.0
    var updateFrequence: Float = 1.0 / 60.0
    var assetVideoTrackReader: AVAssetReaderTrackOutput?
    var assetReader: AVAssetReader?
    var displayLink: CADisplayLink?
    var lastUpdateInterval: TimeInterval = Date.timeIntervalSinceReferenceDate
    var didCaptureFrame: Handler?

    init(pathToRecording: String) {
        super.init()
        assetPath = pathToRecording
    }

    func setupAsset(url: URL) {
        let asset = AVAsset(url: url)

        asset.loadValuesAsynchronously(forKeys: ["tracks"]) { [weak self] in
            print("loadValuesAsynchronously worked")

            var error: NSError?
            guard asset.statusOfValue(forKey: "tracks", error: &error) == AVKeyValueStatus.loaded
                else {
                    print("\(error)")
                    return
            }

            if let firstVideoTrack = asset.tracks(withMediaType: AVMediaType.video).first {
                print("found at least one video track")

                if let self = self {
                    self.assetFrameRate = firstVideoTrack.nominalFrameRate
                    self.updateFrequence = 1.0 / self.assetFrameRate
                    self.assetReader = try! AVAssetReader(asset: asset)
                    let outputSettings = [(kCVPixelBufferPixelFormatTypeKey as String) : NSNumber(value: kCVPixelFormatType_32BGRA)]

                    self.assetVideoTrackReader = AVAssetReaderTrackOutput(track: firstVideoTrack, outputSettings: outputSettings)
                    self.assetReader?.add(self.assetVideoTrackReader!)
                    self.assetReader?.startReading()
                }
            }
        }
    }

    func start() {
        // begin reading from the file and sending frames to the delegate
        print("start()")

        let fileURL = URL(fileURLWithPath: assetPath!)
        setupAsset(url: fileURL)
        displayLink = CADisplayLink(target: self, selector: #selector(self.updateOnDisplayLink))
        displayLink!.add(to: .current, forMode: RunLoopMode.commonModes)
    }

    func stop() {
        // stop reading
    }

    var focalLength: Float {
        return iPhoneXBackFacingCameraFocalLength
    }

    var fieldOfView: Float {
        return iPhoneXBackFacingCameraFoV
    }

    // avic - call this
    // didCaptureFrame?(sampleBuffer)
    // with sampleBuffer: CMSampleBuffer

    @objc func updateOnDisplayLink(displaylink: CADisplayLink) {
        guard self.assetReader?.status == AVAssetReaderStatus.reading else {
            return

        }
        let now = Date.timeIntervalSinceReferenceDate
        let timeElapsed = Float(now - lastUpdateInterval)

        if (timeElapsed >= self.updateFrequence) {
            print("timeElapsed: \(timeElapsed) rate: \(1.0 / timeElapsed)")
            if let nextSampleBuffer = self.assetVideoTrackReader?.copyNextSampleBuffer() {
                print("RecordedVideoSampler didCaptureFrame")
                //                print("sampleBuffer: \(nextSampleBuffer)")
                didCaptureFrame?(nextSampleBuffer)
                lastUpdateInterval = Date.timeIntervalSinceReferenceDate
            }
        }
    }
}
