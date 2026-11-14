import CoreMotion
import Foundation

/// 진단 세션 동안 걸음 수와 정지·보행 상태를 기록한다. 실제로 움직였는지 판단하는 기준이다.
nonisolated final class MotionDiagnosticsProvider: @unchecked Sendable {
    static let shared = MotionDiagnosticsProvider()

    private let pedometer = CMPedometer()
    private let activityManager = CMMotionActivityManager()
    private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "MotionDiagnosticsProvider"
        queue.maxConcurrentOperationCount = 1
        return queue
    }()

    func start(recorder: LocationDiagnosticsRecorder, from startDate: Date) {
        if CMPedometer.isStepCountingAvailable() {
            pedometer.startUpdates(from: startDate) { data, error in
                if let error {
                    recorder.append(.event(.init(at: Date(), name: "pedometer_error",
                                                 detail: ["message": error.localizedDescription])))
                    return
                }
                guard let data else { return }
                recorder.append(.motion(.init(
                    at: Date(), startDate: data.startDate, endDate: data.endDate,
                    steps: data.numberOfSteps.intValue, distance: data.distance?.doubleValue,
                    cadence: data.currentCadence?.doubleValue)))
            }
        } else {
            recorder.append(.event(.init(at: Date(), name: "pedometer_unavailable")))
        }
        if CMMotionActivityManager.isActivityAvailable() {
            activityManager.startActivityUpdates(to: queue) { activity in
                guard let activity else { return }
                recorder.append(.activity(.init(
                    at: Date(), startDate: activity.startDate, isStationary: activity.stationary,
                    isWalking: activity.walking, isRunning: activity.running, isAutomotive: activity.automotive,
                    isCycling: activity.cycling, isUnknown: activity.unknown,
                    confidence: activity.confidence.rawValue)))
            }
        } else {
            recorder.append(.event(.init(at: Date(), name: "activity_unavailable")))
        }
    }

    func stop() {
        pedometer.stopUpdates()
        activityManager.stopActivityUpdates()
    }
}
