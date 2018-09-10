//
//  ModelPerformance.swift
//  VisionSDK
//
//  Created by Alexander Pristavko on 9/4/18.
//  Copyright © 2018 Mapbox. All rights reserved.
//

import Foundation
import UIKit

/**
 Enumeration which determines whether SDK should adapt its performance to environmental changes (acceleration/deceleration, standing time) or stay fixed.
*/
public enum ModelPerformanceMode {
    /**
        Fixed.
    */
    case fixed
    /**
        Dynamic. It depends on speed. Variable from ModelPerformanceRate.low (0 km/h) to VisionManager's performance property (90 km/h).
    */
    case dynamic
}

/**
 Enumeration which determines performance rate of the specific model. These are high-level settings that translates into adjustment of FPS for ML model inference.
*/
public enum ModelPerformanceRate {
    /**
        Low.
    */
    case low
    /**
        Medium.
    */
    case medium
    /**
        High.
    */
    case high
}

/**
 Structure representing performance setting for tasks related to specific ML model. It’s defined as a combination of mode and rate.
*/
public struct ModelPerformance {
    
    /**
        Performance Mode.
    */
    public let mode: ModelPerformanceMode
    /**
        Performance Rate
    */
    public let rate: ModelPerformanceRate

    /**
        Initializer.
    */
    public init(mode: ModelPerformanceMode, rate: ModelPerformanceRate) {
        self.mode = mode
        self.rate = rate
    }
}

enum ModelType {
    case segmentation, detection
}

enum CoreModelPerformance {
    case fixed(fps: Float)
    case dynamic(minFps: Float, maxFps: Float)
}

struct ModelPerformanceResolver {
    private struct PerformanceEntry {
        let low: Float
        let high: Float
        
        func fps(for rate: ModelPerformanceRate) -> Float {
            switch rate {
            case .low:
                return low
            case .medium:
                return (low + high) / 2
            case .high:
                return high
            }
        }
    }
    
    private static let isTopDevice = UIDevice.current.isTopDevice
    
    private static let segmentationHighEnd   = PerformanceEntry(low: 2, high: 7)
    private static let detectionHighEnd      = PerformanceEntry(low: 4, high: 12)
    
    private static let segmentationLowEnd    = PerformanceEntry(low: 2, high: 5)
    private static let detectionLowEnd       = PerformanceEntry(low: 4, high: 11)
    
    private static func performanceEntry(for model: ModelType) -> PerformanceEntry {
        switch model {
        case .segmentation:
            return isTopDevice ? segmentationHighEnd : segmentationLowEnd
        case .detection:
            return isTopDevice ? detectionHighEnd : detectionLowEnd
        }
    }
    
    static func coreModelPerformance(for model: ModelType, with performance: ModelPerformance) -> CoreModelPerformance {
        let entry = performanceEntry(for: model)
        
        switch performance.mode {
        case .fixed:
            return .fixed(fps: entry.fps(for: performance.rate))
        case .dynamic:
            let minFps = entry.fps(for: .low)
            let maxFps = entry.fps(for: performance.rate)
            return .dynamic(minFps: minFps, maxFps: maxFps)
        }
    }
}