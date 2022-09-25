//
//  LHKWorkoutSessionManager.swift
//  
//
//  Created by Justin Honda on 3/12/22.
//

import Foundation
#if !os(macOS) && os(watchOS)
import HealthKit

enum LHKWorkoutSessionError: Error {
    case unknown
    case failedToStartWorkoutSession(with: Error)
}

public final class LHKWorkoutSessionManager: NSObject {
    
    // MARK: - Properties
    
    @Published private(set) public var heartRate: Double = 0
    @Published private(set) public var avgHeartRate: Double = 0
    
    private(set) public var workoutSession: HKWorkoutSession!
    private(set) public var workoutBuilder: HKLiveWorkoutBuilder!
    private(set) public var workoutRouteBuilder: HKWorkoutRouteBuilder!
    private(set) public var workout: HKWorkout!
    private(set) public var startDate: Date?
    private(set) public var endDate: Date?
    
    // MARK: - Public
    
    public init(workoutConfiguration: HKWorkoutConfiguration) {
        self.workoutConfiguration = workoutConfiguration
    }
    
    public func prepare() throws {
        try configureIfNeeded()
        workoutSession.prepare()
    }
    
    public func start() throws {
        startDate = .now
        
        try configureIfNeeded()
        
        workoutSession.startActivity(with: startDate!)
        
        workoutBuilder.beginCollection(withStart: startDate!) { _, error in
            if let error = error {
                debugPrint("******* Workout builder began collection failed with error *******\n", error)
            } else {
                debugPrint("******* Workout builder successfully began collection *******")
            }
        }
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            self.streamingQueries.insert(self.createStreamingHeartRateQuery(with: self.startDate!))
        }
    }
    
    /// Will not be using for MarineFit
    public func pause() {
        streamingQueries.forEach { healthStore.stop($0) }
        streamingQueries.removeAll()
        workoutSession.pause()
    }
    
    /// Will not be using for MarineFit
    public func resume() {
        let resumeDate = Date.now
        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self = self else { return }
            self.streamingQueries.insert(
                self.createStreamingHeartRateQuery(with: resumeDate)
            )
        }
        workoutSession.resume()
    }
    
    public func stop() {
        endDate = .now
        streamingQueries.forEach { healthStore.stop($0) }
        streamingQueries.removeAll()
        workoutSession.end()
    }
    
    // MARK: - Private
    
    private let workoutConfiguration: HKWorkoutConfiguration
    private var streamingQueries = Set<HKQuery>()
    
    private func configureIfNeeded() throws {
        guard workoutSession == nil else {
            return
        }
        
        do {
            workoutSession = try .init(healthStore: healthStore, configuration: workoutConfiguration)
            workoutRouteBuilder = .init(healthStore: healthStore, device: nil)
            workoutBuilder = workoutSession.associatedWorkoutBuilder()
            
            workoutBuilder.shouldCollectWorkoutEvents = true
            workoutBuilder.dataSource = .init(healthStore: healthStore, workoutConfiguration: workoutConfiguration)
            workoutBuilder.delegate = self
            workoutSession.delegate = self
        } catch {
            throw LHKWorkoutSessionError.failedToStartWorkoutSession(with: error)
        }
    }
    
}

// MARK: - Queries

extension LHKWorkoutSessionManager {
    private func createStreamingHeartRateQuery(with date: Date) -> HKQuery {
        let predicate = HKQuery.predicateForSamples(withStart: date, end: nil, options: [.strictStartDate])
        let quantityType = HKQuantityType.init(.heartRate)
        let anchor = HKQueryAnchor(fromValue: 0)
        let anchoredQuery = HKAnchoredObjectQuery(type: quantityType, predicate: predicate, anchor: anchor, limit: HKObjectQueryNoLimit) { anchoredObjectQuery, samples, deletedObject, queryAnchor, error in
        }
        
        anchoredQuery.updateHandler = { anchoredObjectQuery, samples, deletedObject, queryAnchor, error in }
        
        healthStore.execute(anchoredQuery)
        
        return anchoredQuery
    }
}

// MARK: - HKWorkoutSessionDelegate

extension LHKWorkoutSessionManager: HKWorkoutSessionDelegate {
    
    private func endCollection(at date: Date) async throws {
        try await workoutBuilder.endCollection(at: date)
    }
    
    public func workoutSession(_ workoutSession: HKWorkoutSession,
                               didChangeTo toState: HKWorkoutSessionState,
                               from fromState: HKWorkoutSessionState,
                               date: Date
    ) {
        debugPrint("Workout session changed from state: \(fromState.rawValue)")
        debugPrint("Workout session changed to state:   \(toState.rawValue)")
        switch toState {
            case .notStarted: break
            case .running: break
            case .ended:
            workout = .init(activityType: workoutConfiguration.activityType, start: workoutSession.startDate ?? startDate!, end: date)
            workoutBuilder.endCollection(withEnd: date) { [weak self] _, error in
                guard let self = self else { return }
                if let error = error {
                    print("Error ending HKWorkoutBuilder collection: \( error.localizedDescription)")
                } else {
                    self.workoutBuilder.finishWorkout(completion: { hkWorkout, error in
                        if let error = error {
                            print("Error finishing workout: \(error)")
                        } else {
                            self.workoutRouteBuilder.finishRoute(with: hkWorkout ?? self.workout, metadata: nil) { route, error in
                                if let error = error {
                                    print("Error finishing route: \(error)")
                                } else {
                                    print("Successfully finised route: \(String(describing: route))")
                                }
                            }
                        }
                    })
                }
            }
            case .paused: break
            case .prepared: break
            case .stopped: break
            @unknown default:
                fatalError("Have not yet implemented support for state: \(toState)")
        }
    }
    
    public func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        debugPrint("Workout session \(workoutSession) failed with error: \(error.localizedDescription)")
    }
    
}

// MARK: - HKLiveWorkoutBuilderDelegate

extension LHKWorkoutSessionManager: HKLiveWorkoutBuilderDelegate {
    
    public func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) { }
    
    public func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        collectedTypes
            .compactMap { $0 as? HKQuantityType }
            .lazy
            .filter { $0.identifier == HKQuantityType.quantityType(forIdentifier: .heartRate)?.identifier }
            .forEach { [weak self] heartRateQuantityType in
                if let statistics = workoutBuilder.statistics(for: heartRateQuantityType),
                   let heartRateValue = statistics.mostRecentQuantity()?.doubleValue(for: .countPerMin) {
                    
                    self?.heartRate = heartRateValue
                    
                    if let avgHeartRateValue = statistics.averageQuantity()?.doubleValue(for: .countPerMin) {
                        self?.avgHeartRate = avgHeartRateValue
                    }
                }
            }
    }
}
#endif
