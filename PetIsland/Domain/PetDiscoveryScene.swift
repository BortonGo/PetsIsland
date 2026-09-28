import Foundation
import CoreGraphics

/// A foreground illustration of the saved walk, not another simulation or save file.
/// Sampling the same walk/date always restores the same position after reopening the sheet.
struct PetDiscoveryScenePlan {
    enum Activity: Equatable {
        case walking, flowers, bush, stones, waves, reeds, roots, log, mushrooms
        case lookingAround, headingHome, returned
    }

    struct Stop: Equatable {
        let point: CGPoint
        let landmark: CGPoint
        let activity: Activity
        var facing: PetDirection { landmark.x < point.x ? .left : .right }
    }

    struct Frame: Equatable {
        let position: CGPoint
        let direction: PetDirection
        let activity: Activity
        let destination: Activity
        let travelOffset: CGSize
        let actionTime: TimeInterval
        let movementProgress: Double
        var isMoving: Bool { activity == .walking || activity == .headingHome }
        var isHome: Bool { activity == .returned }
        func travelledDistance(in size: CGSize) -> Double {
            hypot(travelOffset.width * size.width, travelOffset.height * size.height)
        }
    }

    static let home = CGPoint(x: 0.16, y: 0.84)
    static let legDuration: TimeInterval = 15
    static let movingDuration: TimeInterval = 9
    static let cycleDuration: TimeInterval = 60
    let walk: PetDiscoveryWalk
    let stops: [Stop]
    private let itinerary: [Stop]

    init(walk: PetDiscoveryWalk) {
        self.walk = walk
        stops = Self.stops(for: walk.route)
        let home = Stop(point: Self.home, landmark: CGPoint(x: 0.25, y: 0.8), activity: .lookingAround)
        // UUID bytes are stable across launches; Swift's randomized hash is not.
        let reverse = walk.id.uuid.0.isMultiple(of: 2)
        itinerary = [home] + (reverse ? Array(stops.reversed()) : stops)
    }

    static func stops(for route: PetWalkRoute) -> [Stop] {
        switch route {
        case .garden:
            [Stop(point: CGPoint(x: 0.30, y: 0.74), landmark: CGPoint(x: 0.43, y: 0.74), activity: .flowers),
             Stop(point: CGPoint(x: 0.75, y: 0.77), landmark: CGPoint(x: 0.87, y: 0.77), activity: .bush),
             Stop(point: CGPoint(x: 0.55, y: 0.87), landmark: CGPoint(x: 0.43, y: 0.87), activity: .stones)]
        case .shore:
            [Stop(point: CGPoint(x: 0.28, y: 0.82), landmark: CGPoint(x: 0.40, y: 0.82), activity: .stones),
             Stop(point: CGPoint(x: 0.60, y: 0.75), landmark: CGPoint(x: 0.49, y: 0.63), activity: .waves),
             Stop(point: CGPoint(x: 0.76, y: 0.84), landmark: CGPoint(x: 0.88, y: 0.84), activity: .reeds)]
        case .grove:
            [Stop(point: CGPoint(x: 0.30, y: 0.76), landmark: CGPoint(x: 0.17, y: 0.76), activity: .roots),
             Stop(point: CGPoint(x: 0.71, y: 0.74), landmark: CGPoint(x: 0.84, y: 0.74), activity: .mushrooms),
             Stop(point: CGPoint(x: 0.57, y: 0.88), landmark: CGPoint(x: 0.43, y: 0.88), activity: .log)]
        }
    }

    func frame(at date: Date) -> Frame {
        guard date.timeIntervalSinceReferenceDate.isFinite else { return regularFrame(elapsed: 0) }
        let duration = walk.endsAt.timeIntervalSince(walk.startedAt)
        let elapsed = min(max(date.timeIntervalSince(walk.startedAt), 0), duration)
        if elapsed >= duration {
            return Frame(position: Self.home, direction: .left, activity: .returned,
                         destination: .returned, travelOffset: .zero, actionTime: 0, movementProgress: 0)
        }
        let returnDuration = min(12, duration * 0.2)
        let returnStart = duration - returnDuration
        if elapsed >= returnStart {
            let from = regularFrame(elapsed: returnStart).position
            return movingFrame(from: from, to: Self.home, progress: (elapsed - returnStart) / returnDuration,
                               activity: .headingHome, destination: .returned)
        }
        return regularFrame(elapsed: elapsed)
    }

    private func regularFrame(elapsed: TimeInterval) -> Frame {
        let clock = elapsed.truncatingRemainder(dividingBy: Self.cycleDuration)
        let index = Int(clock / Self.legDuration)
        let from = itinerary[index], to = itinerary[(index + 1) % itinerary.count]
        let local = clock.truncatingRemainder(dividingBy: Self.legDuration)
        if local < Self.movingDuration {
            return movingFrame(from: from.point, to: to.point, progress: local / Self.movingDuration,
                               activity: .walking, destination: to.activity)
        }
        return Frame(position: to.point, direction: to.facing, activity: to.activity,
                     destination: to.activity, travelOffset: .zero, actionTime: local - Self.movingDuration,
                     movementProgress: 0)
    }

    private func movingFrame(from: CGPoint, to: CGPoint, progress: Double,
                             activity: Activity, destination: Activity) -> Frame {
        let t = min(max(progress, 0), 1)
        let eased = t * t * (3 - 2 * t)
        return Frame(position: CGPoint(x: from.x + (to.x - from.x) * eased,
                                       y: from.y + (to.y - from.y) * eased),
                     direction: to.x < from.x ? .left : .right, activity: activity, destination: destination,
                     travelOffset: CGSize(width: (to.x - from.x) * eased, height: (to.y - from.y) * eased),
                     actionTime: 0, movementProgress: eased)
    }
}
