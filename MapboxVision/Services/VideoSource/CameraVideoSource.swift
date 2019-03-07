//
//  CameraVideoSource.swift
//  cv-assist-ios
//
//  Created by Maksim on 12/11/17.
//  Copyright © 2017 Mapbox. All rights reserved.
//

import Foundation
import AVFoundation
import MapboxVisionCore

private let imageOutputFormat = Image.Format.BGRA

open class CameraVideoSource: NSObject {
    
    public let cameraSession: AVCaptureSession
    
    public init(preset: AVCaptureSession.Preset = .iFrame960x540) {
        self.cameraSession = AVCaptureSession()
        self.camera = AVCaptureDevice.default(for: .video)
        
        super.init()
        
        configureSession(preset: preset)
        
        orientationChanged()
        NotificationCenter.default.addObserver(self, selector: #selector(orientationChanged),
                                               name: .UIDeviceOrientationDidChange, object: nil)
    }
    
    public func start() {
        guard !cameraSession.isRunning else { return }
        cameraSession.startRunning()
    }
    
    public func stop() {
        guard !cameraSession.isRunning else { return }
        cameraSession.startRunning()
    }
    
    // MARK: - Private
    
    private struct Observation {
        weak var observer: VideoSourceObserver?
    }
    
    private let camera: AVCaptureDevice?
    private var dataOutput: AVCaptureVideoDataOutput?
    
    private var observations = [ObjectIdentifier : Observation]()
    
    private func configureSession(preset: AVCaptureSession.Preset) {
        
        guard let captureDevice = camera
            else { return }
        
        guard let deviceInput = try? AVCaptureDeviceInput(device: captureDevice)
            else { return }
        
        cameraSession.beginConfiguration()
        
        cameraSession.sessionPreset = preset
        
        if cameraSession.canAddInput(deviceInput) {
            cameraSession.addInput(deviceInput)
        }
        
        let dataOutput = AVCaptureVideoDataOutput()
        dataOutput.videoSettings = [(kCVPixelBufferPixelFormatTypeKey as String) : NSNumber(value: imageOutputFormat.pixelFormatType)]
        dataOutput.alwaysDiscardsLateVideoFrames = true
        
        if cameraSession.canAddOutput(dataOutput) {
            cameraSession.addOutput(dataOutput)
        }
        
        if let connection = dataOutput.connection(with: .video), connection.isCameraIntrinsicMatrixDeliverySupported {
            connection.isCameraIntrinsicMatrixDeliveryEnabled = true
        }
        
        cameraSession.commitConfiguration()
        
        let queue = DispatchQueue(label: "com.mapbox.videoQueue")
        dataOutput.setSampleBufferDelegate(self, queue: queue)
        
        self.dataOutput = dataOutput
    }
    
    private func getCameraParameters(sampleBuffer: CMSampleBuffer) -> CameraParameters? {
        guard let pixelBuffer = sampleBuffer.pixelBuffer else { return nil }
        
        let width = pixelBuffer.width
        let height = pixelBuffer.height
        
        let focalPixelX: Float
        let focalPixelY: Float
        
        if let attachment = CMGetAttachment(sampleBuffer, kCMSampleBufferAttachmentKey_CameraIntrinsicMatrix, nil) as? Data {
            let matrix: matrix_float3x3 = attachment.withUnsafeBytes { $0.pointee }
            focalPixelX = matrix[0,0]
            focalPixelY = matrix[1,1]
        } else if let fov = formatFieldOfView {
            let pixel = CameraVideoSource.focalPixel(fov: fov, dimension: width)
            focalPixelX = pixel
            focalPixelY = pixel
        } else {
            focalPixelX = -1
            focalPixelY = -1
        }
        
        return CameraParameters(width: width, height: height, focalXPixels: focalPixelX, focalYPixels: focalPixelY)
    }
    
    private func notify(closure: (VideoSourceObserver) -> Void) {
        observations.forEach { (id, observation) in
            guard let observer = observation.observer else {
                observations.removeValue(forKey: id)
                return
            }
            closure(observer)
        }
    }
    
    private var formatFieldOfView: Float? {
        guard let fov = camera?.activeFormat.videoFieldOfView else { return nil }
        return fov > 0 ? fov : nil
    }
    
    private static func focalPixel(fov: Float, dimension: Int) -> Float {
        let measurement = Measurement(value: Double(fov), unit: UnitAngle.degrees)
        return (Float(dimension) / 2) / tan(Float(measurement.converted(to: .radians).value) / 2)
    }
    
    // MARK: - Observations
    
    @objc private func orientationChanged() {
        dataOutput?.connection(with: .video)?.set(deviceOrientation: UIDevice.current.orientation)
    }
}

extension CameraVideoSource: VideoSource {
    public func add(observer: VideoSourceObserver) {
        let id = ObjectIdentifier(observer)
        observations[id] = Observation(observer: observer)
    }
    
    public func remove(observer: VideoSourceObserver) {
        let id = ObjectIdentifier(observer)
        observations.removeValue(forKey: id)
    }
    
    public var isExternal: Bool {
        return false
    }
}

extension CameraVideoSource: AVCaptureVideoDataOutputSampleBufferDelegate {
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        notify { (observer) in
            let sample = VideoSample(buffer: sampleBuffer, format: imageOutputFormat)
            observer.videoSource(self, didOutput: sample)
            
            if let cameraParameters = getCameraParameters(sampleBuffer: sampleBuffer) {
                observer.videoSource(self, didOutput: cameraParameters)
            }
        }
    }
    
    public func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        var mode: CMAttachmentMode = 0
        guard let reason = CMGetAttachment(sampleBuffer, kCMSampleBufferAttachmentKey_DroppedFrameReason, &mode) else { return }
        print("Sample buffer was dropped. Reason: \(reason)")
    }
}

private extension Image.Format {
    var pixelFormatType: OSType {
        switch self {
        case .unknown:
            return 0
        case .RGBA:
            return kCVPixelFormatType_32RGBA
        case .BGRA:
            return kCVPixelFormatType_32BGRA
        case .RGB:
            return kCVPixelFormatType_24RGB
        case .BGR:
            return kCVPixelFormatType_24BGR
        case .grayscale8:
            return kCVPixelFormatType_8Indexed
        }
    }
}
