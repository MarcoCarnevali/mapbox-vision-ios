# Changelog

## 0.5.0 - Unreleased
- Added support for UK country
- Added support for setting attitudeOrient via DeviceMotionData
- Changed World-Pixel transformation methods to return optional values
- Changed World-Geo transformation methods to return optional values
- Changed implementation of `DeviceInfoProvider` provider in order to make device's id persistent
- Changed implementation of `DeviceChecker` to increase performance on devices with A12 Bionic SoC
- Fixed deleting binary telemetry while moving it after recording is finished
- Removed `MapboxNavigation` dependency

## 0.4.1

### Vision
- Fixed a crash that may happen on creating or destroying `VisionARManager` or `VisionSafetyManager`
- Fixed incorrect `ARCamera` values during replaying recorded sessions with `VisionReplayManager`

## 0.4.0

### Vision
- Added `startRecording` and `stopRecording` methods on `VisionManager` to record sessions.
- Added `VisionReplayManager` class for replaying recorded sessions.
- Changed the type of `visionManager` parameter in every `VisionManagerDelegate` method to `VisionManagerProtocol`.
- Changed `boundingBox` property on `MBVDetection` to store normalized relative coordinates.
- Fixed `CVPixelBuffer` memory leak.

### AR
- Added `set(laneLength:)` method on `VisionARManager` to customize the length of `ARLane`.
