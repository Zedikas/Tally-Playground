import Foundation

extension DateComponents {
    /// Convenience initializer matching the readable weekday-first call sites used by Tally.
    init(weekday: Int, hour: Int, minute: Int) {
        self.init()
        self.hour = hour
        self.minute = minute
        self.weekday = weekday
    }
}
