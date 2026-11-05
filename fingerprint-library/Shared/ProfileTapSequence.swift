import Foundation

nonisolated struct ProfileTapSequence {
    static let interval: TimeInterval = 0.5
    private var count = 0
    private var previousTap: TimeInterval?

    mutating func register(at time: TimeInterval) -> Bool {
        if let previousTap, (0...Self.interval).contains(time - previousTap) {
            count += 1
        } else {
            count = 1
        }
        previousTap = time
        guard count == 5 else { return false }
        reset()
        return true
    }

    mutating func reset() {
        count = 0
        previousTap = nil
    }
}
