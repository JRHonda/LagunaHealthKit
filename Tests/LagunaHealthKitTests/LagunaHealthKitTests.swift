import XCTest
@testable import LagunaHealthKit
#if !os(macOS)

import HealthKit

final class LHKHealthPermissionsHandlerTests: XCTestCase {

    // MARK: - Test Properties
    
    private lazy var shareTypes: Set<HKSampleType> = Set([
        HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
        HKObjectType.quantityType(forIdentifier: .basalEnergyBurned)!,
        HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!,
        HKObjectType.quantityType(forIdentifier: .heartRate)!,
        HKObjectType.workoutType(),
        HKSeriesType.workoutType(),
        HKSeriesType.workoutRoute()
    ])
    
    private lazy var readTypes: Set<HKObjectType> = Set([
        HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
        HKObjectType.quantityType(forIdentifier: .appleExerciseTime)!,
        HKObjectType.quantityType(forIdentifier: .basalEnergyBurned)!,
        HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!,
        HKObjectType.quantityType(forIdentifier: .heartRate)!,
        HKObjectType.activitySummaryType(),
        HKObjectType.workoutType(),
        HKSeriesType.workoutRoute()
    ])
    
    // MARK: - Tests
    
    func test_onlyOneInstanceOfHKHealthStoreExists() {
        let instanceOne = healthStore
        let instanceTwo = healthStore
        
        // identity equality
        XCTAssert(instanceOne === instanceTwo)
    }
}

#endif
