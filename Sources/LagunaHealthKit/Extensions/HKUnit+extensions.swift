//
//  HKUnit+extensions.swift
//  
//
//  Created by Justin Honda on 3/12/22.
//

#if !os(macOS)

import HealthKit

public extension HKUnit {
    class var countPerMin: Self { Self(from: "count/min") }
}

#endif
