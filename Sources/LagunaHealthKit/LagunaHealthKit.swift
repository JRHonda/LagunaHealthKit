#if !os(macOS)

import HealthKit

public enum LHKHealthStore {
    /// Apps should use a single instance of `HKHealthStore`
    internal static let shared = HKHealthStore()
}

#endif
