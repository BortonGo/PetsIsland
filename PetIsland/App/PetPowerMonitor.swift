import Combine
import Foundation
import UIKit

/// Foreground pet scenes can render less often without changing their clocks,
/// gait distance or artwork. System surfaces and arcade physics are independent.
enum PetAnimationPowerPolicy: Equatable, Sendable {
    case normal, constrained

    init(lowPowerMode: Bool, thermalState: ProcessInfo.ThermalState) {
        switch thermalState {
        case .nominal, .fair: self = lowPowerMode ? .constrained : .normal
        case .serious, .critical: self = .constrained
        @unknown default: self = .constrained
        }
    }

    var framesPerSecond: Int { self == .normal ? 60 : 30 }
    var frameInterval: TimeInterval { 1 / Double(framesPerSecond) }

    static var current: Self {
        Self(lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
             thermalState: ProcessInfo.processInfo.thermalState)
    }
}

/// One event-driven observer for the app; no polling or background timer.
@MainActor
final class PetPowerMonitor: ObservableObject {
    static let shared = PetPowerMonitor()
    @Published private(set) var policy: PetAnimationPowerPolicy
    private let readPolicy: () -> PetAnimationPowerPolicy
    private var observation: AnyCancellable?

    init(center: NotificationCenter = .default,
         readPolicy: @escaping () -> PetAnimationPowerPolicy = { .current }) {
        self.readPolicy = readPolicy
        policy = readPolicy()
        observation = Publishers.Merge3(
            center.publisher(for: .NSProcessInfoPowerStateDidChange),
            center.publisher(for: ProcessInfo.thermalStateDidChangeNotification),
            center.publisher(for: UIApplication.didBecomeActiveNotification)
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in self?.refresh() }
    }

    private func refresh() {
        let current = readPolicy()
        if current != policy { policy = current }
    }
}
