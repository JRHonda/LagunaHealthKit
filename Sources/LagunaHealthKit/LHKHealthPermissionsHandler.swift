//
//  HealthPermissionsHandler.swift
//  
//
//  Created by Justin Honda on 1/25/22.
//

#if !os(macOS)
import HealthKit

public let healthStore = HKHealthStore()

public enum LHKHealthKitAuthorizationError: Error {
    case unknown
    case healthDataUnavailable
    case systemError(Error)
}

public struct LHKHealthPermissionsHandler {
    
    // MARK: - Public Methods
    
    public static func requestAuthorization(with shareTypes: Set<HKSampleType>, readTypes: Set<HKObjectType>, _ completion: @escaping (Result<Bool, LHKHealthKitAuthorizationError>) -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else {
            completion(.failure(.healthDataUnavailable))
            return
        }
        
        healthStore.requestAuthorization(toShare: shareTypes, read: readTypes) { success, error in
            if let error = error {
                completion(.failure(.systemError(error)))
            }
            
            guard success else {
                completion(.failure(.unknown))
                return
            }
            
            completion(.success(success))
        }
    }
}
#endif
