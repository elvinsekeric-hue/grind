import Foundation

/// Decides when to grab a timelapse frame. Keeps at most `maxFrames` frames:
/// when the limit is hit, every second frame is dropped and the interval doubles.
/// That way a 20 minute and a 6 hour session both end up as a ~45 s video.
public struct FrameSchedule: Codable, Equatable, Sendable {
    public let baseInterval: Double
    public let maxFrames: Int
    public private(set) var interval: Double
    public private(set) var kept: [Int]
    public private(set) var nextID: Int

    public init(baseInterval: Double = 0.5, maxFrames: Int = 2400) {
        self.baseInterval = baseInterval
        self.maxFrames = max(4, maxFrames - maxFrames % 2)
        self.interval = baseInterval
        self.kept = []
        self.nextID = 0
    }

    public func shouldCapture(secondsSinceLast: Double) -> Bool {
        secondsSinceLast >= interval
    }

    /// Registers a new frame. Returns its id and the ids that must be deleted.
    public mutating func appendFrame() -> (id: Int, dropped: [Int]) {
        let id = nextID
        nextID += 1
        kept.append(id)
        guard kept.count >= maxFrames else { return (id, []) }

        var keep: [Int] = []
        var dropped: [Int] = []
        keep.reserveCapacity(kept.count / 2 + 1)
        for (index, frame) in kept.enumerated() {
            if index % 2 == 0 { keep.append(frame) } else { dropped.append(frame) }
        }
        kept = keep
        interval *= 2
        return (id, dropped)
    }

    /// Playback rate so the finished video lasts about `targetSeconds`.
    public static func playbackFPS(frameCount: Int, targetSeconds: Double = 45) -> Int {
        guard frameCount > 0 else { return 24 }
        let fps = Int((Double(frameCount) / targetSeconds).rounded())
        return min(60, max(24, fps))
    }
}
