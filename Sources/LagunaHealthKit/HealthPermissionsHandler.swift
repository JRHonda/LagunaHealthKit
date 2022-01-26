//
//  HealthPermissionsHandler.swift
//  
//
//  Created by Justin Honda on 1/25/22.
//

import HealthKit

public enum HealthKitAuthorizationError: Error {
    case unknown
    case healthDataUnavailable
    case systemError(Error)
}

struct HealthPermissionsHandler {
    let shareTypes: Set<HKSampleType>
    let readTypes: Set<HKObjectType>
    let healthStore = HKHealthStore()
    
    func requestAuthorization(_ completion: @escaping (Result<Bool, HealthKitAuthorizationError>) -> Void) {
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
