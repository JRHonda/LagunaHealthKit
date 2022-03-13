//
//  LHKWorkoutSessionManager.swift
//  
//
//  Created by Justin Honda on 3/12/22.
//

import HealthKit

enum LHKWorkoutSessionError: Error {
    case unknown
    case failedToStartWorkoutSession(with: Error)
}

public final class LHKWorkoutSessionManager: NSObject {
    
    private(set) public var workoutSession: HKWorkoutSession!
    private(set) public var workoutBuilder: HKLiveWorkoutBuilder!
    private(set) public var workoutRouteBuilder: HKWorkoutRouteBuilder!
    private(set) public var workout: HKWorkout!
    private(set) public var startDate: Date?
    private(set) public var endDate: Date?
    
    private var streamingQueries = Set<HKQuery>()
    
    private lazy var workoutConfiguration: HKWorkoutConfiguration = {
        let workoutConfig = HKWorkoutConfiguration()
        workoutConfig.locationType = .outdoor
        workoutConfig.activityType = .running
        return workoutConfig
    }()
    
    @Published private(set) public var heartRate: Double = 0
    
    public override init() { super.init() }
    
    public func start() throws {
        startDate = .now
        
        do {
            workoutSession      = try .init(healthStore: healthStore, configuration: workoutConfiguration)
            workoutRouteBuilder = .init(healthStore: healthStore, device: nil)
            workoutBuilder      = workoutSession.associatedWorkoutBuilder()
            
            workoutBuilder.shouldCollectWorkoutEvents = true
            workoutBuilder.dataSource                 = .init(healthStore: healthStore, workoutConfiguration: workoutConfiguration)
            workoutBuilder.delegate                   = self
            
            workoutSession.delegate = self
        } catch {
            throw LHKWorkoutSessionError.failedToStartWorkoutSession(with: error)
        }
        
        workoutSession.startActivity(with: startDate!)
        
        workoutBuilder.beginCollection(withStart: startDate!) { _, error in
            if let error = error {
                debugPrint("******* Workout builder began collection failed with error *******\n", error)
            } else {
                debugPrint("******* Workout builder successfully began collection *******")
            }
        }
        
        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self = self else { return }
            self.streamingQueries.insert(self.createStreamingHeartRateQuery(with: self.startDate!))
        }
    }
    
    public func pause() {
        streamingQueries.forEach { healthStore.stop($0) }
        streamingQueries.removeAll()
        workoutSession.pause()
    }
    
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
        
        // *** Required for finishRoute() method of workoutRouteBuilder *** //
        workout = HKWorkout(activityType: workoutConfiguration.activityType, start: startDate!, end: endDate!)
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
                workoutBuilder.endCollection(withEnd: date) { [weak self] _, error in
                    guard let self = self else { return }
                    if let error = error {
                        debugPrint("******* Workout builder end collection error:", error)
                    } else {
                        self.workoutBuilder.finishWorkout(completion: { workout, error in
                            if let error = error {
                                debugPrint("******* Workout builder finish workout error:", error)
                            } else if let workout = workout {
                                debugPrint("******* Workout builder finish workout finished successfully:", workout)
                                // Save HKWorkout in order to finish route of workout route builder
                                healthStore.save(self.workout) { _, error in
                                    if let error = error {
                                        debugPrint("Error saving HKWorkout with healthStore with error:", error)
                                    } else {
                                        self.workoutRouteBuilder.finishRoute(with: self.workout, metadata: nil) { workoutRoute, error in
                                            if let error = error {
                                                // will error if the HKWorkout instance is not saved prior to calling this method
                                                debugPrint("Error finishing workout route with error:", error)
                                            } else if let workoutRoute = workoutRoute {
                                                debugPrint("Successful completion finishing workout route building with route:", workoutRoute)
                                            }
                                        }
                                    }
                                }
                            } else {
                                debugPrint("******* Workout builder workout and error are nil *******")
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
                }
            }
    }
}
