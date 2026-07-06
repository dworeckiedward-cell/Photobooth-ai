import Foundation

/// Phase 4 — motion templates & ramping (blueprint §7.2–7.3).
///
/// The pro look is ONE clear hero beat with eased entry/exit — not chaotic
/// micro-ramps. Templates emit a `RenderTimeline` (multi-segment, per-segment
/// speed/reverse) that the Phase 3 engine already consumes.
///
/// Physics guardrail (§7.2, "flag don't fake"): slow-mo must come from real
/// captured frames. The slowest honest speed is `outputFPS / captureFPS`
/// (120→30 ⇒ 0.25 = 4× slow-mo). Curves asking for less are CLAMPED and the
/// result is flagged (`clamped`) so callers can warn — never silently pretend.

// MARK: - Ramp curves

enum RampCurve: String, CaseIterable, Sendable {
    case gentle, punchy, dramatic

    /// Easing for the ramp-in/out phases: maps linear progress 0…1 (start of
    /// ramp → hero) onto eased progress 0…1.
    func ease(_ t: Double) -> Double {
        let x = min(max(t, 0), 1)
        switch self {
        case .gentle:   // smoothstep — soft both ends
            return x * x * (3 - 2 * x)
        case .punchy:   // ease-in cubic — lingers fast, drops into slow-mo late & hard
            return x * x * x
        case .dramatic: // ease-out cubic — dives toward the hero immediately
            return 1 - pow(1 - x, 3)
        }
    }
}

// MARK: - Templates

enum MotionTemplate: String, CaseIterable, Identifiable, Sendable {
    /// Quick lead-in → hero slow-mo → normal exit.
    case heroSlow
    /// Full pass forward, then the same pass reversed (the 360 classic).
    case reverseBounce
    /// Intro at speed → hero slow → outro at speed (loop-friendly ends).
    case loopPromo

    var id: String { rawValue }

    var label: String {
        switch self {
        case .heroSlow:      "Hero Slow"
        case .reverseBounce: "Reverse Bounce"
        case .loopPromo:     "Loop Promo"
        }
    }

    /// Sub-segment step used to approximate continuous eased ramps
    /// (blueprint: "approximate by fine sub-segment stepping; document the
    /// step resolution"). 0.1 s of SOURCE time per step — 10 steps/second of
    /// ramp, visually smooth at 30 fps output without exploding segment count.
    static let rampStepSeconds: Double = 0.1

    struct Result: Sendable {
        var timeline: RenderTimeline
        /// True when the requested hero speed was physically impossible for
        /// the capture (not enough real frames) and got clamped. Surface a
        /// warning; never fake smoothness.
        var clamped: Bool
        /// The hero (slowest) speed actually used.
        var heroSpeed: Double
    }

    /// Build the timeline for a capture.
    /// - Parameters:
    ///   - captureDuration: raw clip length (s)
    ///   - captureFPS: fps the clip was actually recorded at
    ///   - outputFPS: render output fps (spec: 30)
    ///   - curve: ramp easing preset
    func timeline(
        captureDuration: Double,
        captureFPS: Double,
        outputFPS: Double = 30,
        curve: RampCurve = .gentle
    ) -> Result {
        // Degenerate capture → single honest 1× segment.
        guard captureDuration > 0.4, captureFPS > 0, outputFPS > 0 else {
            return Result(
                timeline: .fullRange(duration: max(captureDuration, 0)),
                clamped: false,
                heroSpeed: 1
            )
        }

        // Physical floor: below this speed we'd need frames we didn't capture.
        let minHonestSpeed = min(outputFPS / captureFPS, 1)
        // The look targets 4× slow-mo at the hero.
        let requestedHero = 0.25
        let heroSpeed = max(requestedHero, minHonestSpeed)
        let clamped = requestedHero < minHonestSpeed

        switch self {
        case .heroSlow:
            // Layout (source time): 20% lead @1× · ramp-down · 35% hero · ramp-up · rest @1×
            let lead = captureDuration * 0.20
            let ramp = min(captureDuration * 0.10, 0.6)
            let hero = captureDuration * 0.35
            var segments: [RenderTimeline.Segment] = []
            var cursor = 0.0
            segments.append(.init(sourceStart: cursor, sourceDuration: lead, speed: 1)); cursor += lead
            segments += Self.rampSegments(from: 1, to: heroSpeed, sourceStart: cursor, sourceDuration: ramp, curve: curve); cursor += ramp
            segments.append(.init(sourceStart: cursor, sourceDuration: hero, speed: heroSpeed)); cursor += hero
            segments += Self.rampSegments(from: heroSpeed, to: 1, sourceStart: cursor, sourceDuration: ramp, curve: curve); cursor += ramp
            let tail = max(captureDuration - cursor, 0)
            if tail > 0.05 { segments.append(.init(sourceStart: cursor, sourceDuration: tail, speed: 1)) }
            return Result(timeline: RenderTimeline(segments: segments), clamped: clamped, heroSpeed: heroSpeed)

        case .reverseBounce:
            // Forward pass at 1×, then the whole take reversed at a slight slow
            // (1.25× duration) so the bounce reads deliberately, not glitchy.
            let forward = RenderTimeline.Segment(sourceStart: 0, sourceDuration: captureDuration, speed: 1)
            let back = RenderTimeline.Segment(
                sourceStart: 0, sourceDuration: captureDuration,
                speed: max(0.8, minHonestSpeed), reversed: true
            )
            return Result(
                timeline: RenderTimeline(segments: [forward, back]),
                clamped: clamped, heroSpeed: heroSpeed
            )

        case .loopPromo:
            // Symmetric: 25% intro @1× · ramp · hero (middle 30%) · ramp · 25% outro @1×.
            // Matching intro/outro speeds make the clip loop cleanly on socials.
            let intro = captureDuration * 0.25
            let ramp = min(captureDuration * 0.10, 0.6)
            let hero = captureDuration * 0.30
            var segments: [RenderTimeline.Segment] = []
            var cursor = 0.0
            segments.append(.init(sourceStart: cursor, sourceDuration: intro, speed: 1)); cursor += intro
            segments += Self.rampSegments(from: 1, to: heroSpeed, sourceStart: cursor, sourceDuration: ramp, curve: curve); cursor += ramp
            segments.append(.init(sourceStart: cursor, sourceDuration: hero, speed: heroSpeed)); cursor += hero
            segments += Self.rampSegments(from: heroSpeed, to: 1, sourceStart: cursor, sourceDuration: ramp, curve: curve); cursor += ramp
            let outro = max(captureDuration - cursor, 0)
            if outro > 0.05 { segments.append(.init(sourceStart: cursor, sourceDuration: outro, speed: 1)) }
            return Result(timeline: RenderTimeline(segments: segments), clamped: clamped, heroSpeed: heroSpeed)
        }
    }

    /// Approximate a continuous eased speed ramp with fine constant-speed
    /// sub-segments (`rampStepSeconds` of source time each). Speeds are
    /// clamped to `min(from,to)…max(from,to)` by construction.
    static func rampSegments(
        from startSpeed: Double,
        to endSpeed: Double,
        sourceStart: Double,
        sourceDuration: Double,
        curve: RampCurve
    ) -> [RenderTimeline.Segment] {
        guard sourceDuration > 0.01 else { return [] }
        let stepCount = max(Int((sourceDuration / rampStepSeconds).rounded()), 2)
        let stepDuration = sourceDuration / Double(stepCount)
        return (0..<stepCount).map { i in
            // Sample the curve at the step midpoint for a fair average speed.
            let t = (Double(i) + 0.5) / Double(stepCount)
            let eased = curve.ease(t)
            let speed = startSpeed + (endSpeed - startSpeed) * eased
            return RenderTimeline.Segment(
                sourceStart: sourceStart + Double(i) * stepDuration,
                sourceDuration: stepDuration,
                speed: speed
            )
        }
    }
}
