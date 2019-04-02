//
// Created by Alexander Pristavko on 2019-03-29.
// Copyright (c) 2019 Mapbox. All rights reserved.
//

import Foundation
import UIKit
import MapboxVision
import MapboxVisionSafety

class OverSpeedingViewController: UIViewController {
    private var videoSource: CameraVideoSource!
    private var visionManager: VisionManager!
    private var visionSafetyManager: VisionSafetyManager!
    
    private let visionViewController = VisionPresentationViewController()
    private var alertView: UIView!
    
    private var location: VehicleLocation?
    private var restrictions: RoadRestrictions?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        addVisionView()
        addAlertView()
        
        videoSource = CameraVideoSource()
        videoSource.add(observer: self)
        
        visionManager = VisionManager.create(videoSource: videoSource)
        visionSafetyManager = VisionSafetyManager.create(visionManager: visionManager, delegate: self)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        visionManager.start(delegate: self)
        videoSource.start()
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        
        videoSource.stop()
        visionManager.stop()
        visionSafetyManager.destroy()
    }
    
    private func addVisionView() {
        addChild(visionViewController)
        view.addSubview(visionViewController.view)
        visionViewController.didMove(toParent: self)
    }
    
    private func addAlertView() {
        alertView = UIImageView(image: UIImage(named: "alert"))
        alertView.isHidden = true
        alertView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(alertView)
        NSLayoutConstraint.activate([
            alertView.topAnchor.constraint(equalToSystemSpacingBelow: view.topAnchor, multiplier: 1),
            view.trailingAnchor.constraint(equalToSystemSpacingAfter: alertView.trailingAnchor, multiplier: 1)
        ])
    }
}

extension OverSpeedingViewController: VisionManagerDelegate, VisionSafetyDelegate {
    func visionManager(_ visionManager: VisionManager, didUpdateVehicleLocation vehicleLocation: VehicleLocation) {
        DispatchQueue.main.async { [weak self] in
            self?.location = vehicleLocation
        }
    }
    
    func onRoadRestrictionsUpdated(manager: VisionSafetyManager, roadRestrictions: RoadRestrictions) {
        DispatchQueue.main.async { [weak self] in
            self?.restrictions = roadRestrictions
        }
    }
    
    func visionManagerDidFinishUpdate(_ visionManager: VisionManager) {
        DispatchQueue.main.async { [weak self] in
            guard let location = self?.location, let restrictions = self?.restrictions else { return }
            
            let isOverSpeeding = location.speed > restrictions.speedLimits.speedLimitRange.max
            self?.alertView.isHidden = !isOverSpeeding
        }
    }
}

extension OverSpeedingViewController: VideoSourceObserver {
    public func videoSource(_ videoSource: VideoSource, didOutput videoSample: VideoSample) {
        DispatchQueue.main.async { [weak self] in
            self?.visionViewController.present(sampleBuffer: videoSample.buffer)
        }
    }
}
