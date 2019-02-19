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
    var assetVideoTrackReader: AVAssetReaderTrackOutput?
    var assetReader: AVAssetReader?
    var displayLink: CADisplayLink?
    var lastUpdateInterval: TimeInterval = 0
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
                    self.assetReader = try! AVAssetReader(asset: asset)
                    let outputSettings = [(kCVPixelBufferPixelFormatTypeKey as String) : NSNumber(value: kCVPixelFormatType_32BGRA)]

                    self.assetVideoTrackReader = AVAssetReaderTrackOutput(track: firstVideoTrack, outputSettings: outputSettings)
                    self.assetReader?.add(self.assetVideoTrackReader!)
                    self.assetReader?.startReading()

                    if let nextSampleBuffer = self.assetVideoTrackReader!.copyNextSampleBuffer() {
                        print(nextSampleBuffer)
                    }
                }
            }
        }
    }

    @objc func update() {
        print("RecordedVideoSampler Updating!")

        if let nextSampleBuffer = assetVideoTrackReader?.copyNextSampleBuffer() {
            print("got a buffer: \(nextSampleBuffer)")
            let now = Date.timeIntervalSinceReferenceDate
            let timeElapsed = now - lastUpdateInterval

            // avic - add some kind of tolerance over 60fps?
            if (timeElapsed <= 1.0 / 60.0) {
                didCaptureFrame?(nextSampleBuffer)
            }
        }

        lastUpdateInterval = Date.timeIntervalSinceReferenceDate
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
        print("RecordedVideoSampler Updating!")

        if let nextSampleBuffer = self.assetVideoTrackReader?.copyNextSampleBuffer() {
            print(nextSampleBuffer)
            let now = Date.timeIntervalSinceReferenceDate
            let timeElapsed = now - lastUpdateInterval

            // avic - add some kind of tolerance over 60fps?
            if (timeElapsed <= 1.0 / 60.0) {
                print("RecordedVideoSampler didCaptureFrame")
                didCaptureFrame?(nextSampleBuffer)
            }
        } else {
            print("AVAssetReader: \(self.assetReader) - AVAssetReaderTrackOutput: \(self.assetVideoTrackReader)")
        }

        //        if let nextSampleBuffer = assetVideoTrackReader?.copyNextSampleBuffer() {
        //            print("got a buffer: \(nextSampleBuffer)")
        //            let now = Date.timeIntervalSinceReferenceDate
        //            let timeElapsed = now - lastUpdateInterval
        //
        //            // avic - add some kind of tolerance over 60fps?
        //            if (timeElapsed <= 1.0 / 60.0) {
        //                didCaptureFrame?(nextSampleBuffer)
        //            }
        //        }
        //
        //        lastUpdateInterval = Date.timeIntervalSinceReferenceDate
    }
}
