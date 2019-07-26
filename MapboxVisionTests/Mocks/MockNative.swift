@testable import MapboxVision
@testable import MapboxVisionNative

class MockNative: VisionManagerNativeProtocol {
    private(set) var isDestroyed: Bool = false

    func setSegmentationFixedFPS(_: Float) {}

    func setSegmentationDynamicFPS(minFPS: Float, maxFPS: Float) {}

    func setDetectionFixedFPS(_: Float) {}

    func setDetectionDynamicFPS(minFPS: Float, maxFPS: Float) {}

    var config = CoreConfig()

    var sensors: SensorsInterface {
        return MockSensors()
    }

    func start(_: VisionDelegate) {}

    func stop() {}

    func destroy() {
        isDestroyed = true
    }

    func getSeconds() -> Float {
        return 0
    }

    func startSavingSession(_ path: String) {}

    func stopSavingSession() {}

    func pixel(toWorld screenCoordinate: Point2D) -> WorldCoordinate? {
        return nil
    }

    func world(toPixel worldCoordinate: WorldCoordinate) -> Point2D? {
        return nil
    }

    func geo(toWorld geoCoordinate: GeoCoordinate) -> WorldCoordinate? {
        return nil
    }

    func world(toGeo worldCoordinates: WorldCoordinate) -> GeoCoordinate? {
        return nil
    }
}
