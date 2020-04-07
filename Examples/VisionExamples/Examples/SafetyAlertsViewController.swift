import MapboxVision
import MapboxVisionSafety
import UIKit

/**
 * "Safety alerts" example demonstrates how to utilize events from MapboxVisionSafetyManager
 * to alert a user about exceeding allowed speed limit and potential collisions with other cars.
 */

// Custom UIView to draw a red bounding boxes
class CollisionDetectionView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)

        // Transparent view with a red border
        backgroundColor = .clear
        layer.borderWidth = 3
        layer.borderColor = UIColor.red.cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

class SafetyAlertsViewController: UIViewController {
    private var visionManager: VisionReplayManager!
    private var visionSafetyManager: VisionSafetyManager!

    private let visionViewController = VisionPresentationViewController()

    private var alertOverspeedingView: UIView!

    private var vehicleState: VehicleState?
    private var speedLimits: SpeedLimits?
    private var carCollisions = [CollisionObject]()

    override func viewDidLoad() {
        super.viewDidLoad()

        // Documents directory path with files uploaded via Finder
        let documentsPath =
            NSSearchPathForDirectoriesInDomains(.documentDirectory,
                                                .userDomainMask,
                                                true).first!
        let path = documentsPath.appending("/safety-alerts-drawing")

        // create VisionReplayManager with a path to recorded session
        visionManager = try? VisionReplayManager.create(recordPath: path)
        // register its delegate
        visionManager.delegate = self

        // create VisionSafetyManager and register as its delegate to receive safety related events
        visionSafetyManager = VisionSafetyManager.create(visionManager: visionManager)
        // register its delegate
        visionSafetyManager.delegate = self

        // configure Vision view to display sample buffers from video source
        visionViewController.set(visionManager: visionManager)
        // add Vision view as a child view
        addVisionView()

        // add view to draw overspeeding alert
        addOverspeedingAlertView()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        visionManager.start()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)

        visionManager.stop()
    }

    deinit {
        // free up VisionManager's resources
        visionManager.destroy()
    }

    private func addVisionView() {
        addChild(visionViewController)
        view.addSubview(visionViewController.view)
        visionViewController.didMove(toParent: self)
    }

    private func addOverspeedingAlertView() {
        alertOverspeedingView = UIImageView(image: UIImage(named: "alert"))
        alertOverspeedingView.isHidden = true
        alertOverspeedingView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(alertOverspeedingView)
        NSLayoutConstraint.activate([
            alertOverspeedingView.topAnchor.constraint(equalToSystemSpacingBelow: view.topAnchor, multiplier: 1),
            view.trailingAnchor.constraint(equalToSystemSpacingAfter: alertOverspeedingView.trailingAnchor, multiplier: 1)
        ])
    }

    // MARK: - Drawing custom collision detection views

    private func clearCollisionStateDrawings() {
        for subview in view.subviews {
            if subview.isKind(of: CollisionDetectionView.self) {
                subview.removeFromSuperview()
            }
        }
    }

    // MARK: - Handle VisionSafety events

    private func updateCollisionDrawing() {
        clearCollisionStateDrawings()

        for carCollision in carCollisions {
            // Calculate absolute coordinates
            let relativeBBox = carCollision.lastDetection.boundingBox
            let frameSize = carCollision.lastFrame.image.size.cgSize

            let bbox = CGRect(x: relativeBBox.origin.x * frameSize.width,
                              y: relativeBBox.origin.y * frameSize.height,
                              width: relativeBBox.size.width * frameSize.width,
                              height: relativeBBox.size.height * frameSize.height)

            // Draw a collision detection alert
            let view = CollisionDetectionView(frame: bbox)
            self.view.addSubview(view)
        }
    }

    private func updateOverspeedingDrawing() {
        // when update is completed all the data has the most current state
        guard let vehicle = self.vehicleState, let limits = self.speedLimits else { return }

        // decide whether speed limit is exceeded by comparing it with the current speed
        let isOverSpeeding = vehicle.speed > limits.speedLimitRange.max
        self.alertOverspeedingView.isHidden = !isOverSpeeding
    }
}

extension SafetyAlertsViewController: VisionManagerDelegate {
    func visionManager(_ visionManager: VisionManagerProtocol,
                       didUpdateVehicleState vehicleState: VehicleState) {
        // dispatch to the main queue in order to sync access to `VehicleState` instance
        DispatchQueue.main.async { [weak self] in
            // save the latest state of the vehicle
            self?.vehicleState = vehicleState
        }
    }

    func visionManagerDidCompleteUpdate(_ visionManager: VisionManagerProtocol) {
        // dispatch to the main queue in order to work with UIKit elements
        DispatchQueue.main.async { [weak self] in
            // update UI elements
            self?.updateOverspeedingDrawing()
            self?.updateCollisionDrawing()
        }
    }
}

extension SafetyAlertsViewController: VisionSafetyManagerDelegate {
    func visionSafetyManager(_ visionSafetyManager: VisionSafetyManager,
                             didUpdateRoadRestrictions roadRestrictions: RoadRestrictions) {
        // dispatch to the main queue in order to sync access to `SpeedLimits` instance
        DispatchQueue.main.async { [weak self] in
            // save currenly applied speed limits
            self?.speedLimits = roadRestrictions.speedLimits
        }
    }

    func visionSafetyManager(_ visionSafetyManager: VisionSafetyManager,
                             didUpdateCollisions collisions: [CollisionObject]) {
        let carCollisions = collisions.filter { $0.object.detectionClass == .car }

        // dispatch to the main queue in order to sync access to `[CollisionObject]` array
        DispatchQueue.main.async { [weak self] in
            // update current collisions state
            self?.carCollisions = carCollisions
        }
    }
}

// This comment is here to assure the correct rendering of code snippets in a public documentation
