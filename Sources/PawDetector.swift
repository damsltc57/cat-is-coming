nonisolated enum PawPattern: Equatable {
    case landing
    case settling
    case crossing
    case singleKeyHold
}

nonisolated struct AutomaticLockRules: Codable, Equatable {
    var landingEnabled = true
    var landingKeyCount = 4
    var landingWindowMS = 150
    var settlingEnabled = true
    var settlingKeyCount = 3
    var settlingWindowMS = 150
    var settlingHoldMS = 200
    var crossingEnabled = true
    var crossingPairWindowMS = 90
    var crossingOverlapMS = 25
    var crossingWindowMS = 1_000
    var singleKeyEnabled = false
    var singleKeyHoldMS = 2_000

    static let keyCountRange = 2...10
    static let pressWindowRange = 20...500
    static let settlingHoldRange = 50...2_000
    static let crossingOverlapRange = 10...500
    static let crossingWindowRange = 100...3_000
    static let singleKeyHoldRange = 1_000...15_000

    mutating func clampThresholds() {
        func clamp(_ value: Int, to range: ClosedRange<Int>) -> Int {
            min(max(value, range.lowerBound), range.upperBound)
        }
        landingKeyCount = clamp(landingKeyCount, to: Self.keyCountRange)
        landingWindowMS = clamp(landingWindowMS, to: Self.pressWindowRange)
        settlingKeyCount = clamp(settlingKeyCount, to: Self.keyCountRange)
        settlingWindowMS = clamp(settlingWindowMS, to: Self.pressWindowRange)
        settlingHoldMS = clamp(settlingHoldMS, to: Self.settlingHoldRange)
        crossingPairWindowMS = clamp(crossingPairWindowMS, to: Self.pressWindowRange)
        crossingOverlapMS = clamp(crossingOverlapMS, to: Self.crossingOverlapRange)
        crossingWindowMS = clamp(crossingWindowMS, to: Self.crossingWindowRange)
        singleKeyHoldMS = clamp(singleKeyHoldMS, to: Self.singleKeyHoldRange)
    }
}

nonisolated struct PawDetector {
    struct Hold {
        let deadline: UInt64
        let pattern: PawPattern
    }

    let rules: AutomaticLockRules
    private struct Step {
        let keys: Set<Int64>
        let startedAt: UInt64
    }

    private var held: [Int64: UInt64] = [:]
    private var waitingForRelease = false
    private var pendingSteps: [Step] = []
    private var firstStep: Step?
    private var singleKeyStartedAt: UInt64?

    init(rules: AutomaticLockRules = .init()) {
        self.rules = rules
    }

    var heldKeys: Dictionary<Int64, UInt64>.Keys { held.keys }

    var pendingHold: Hold? {
        guard !waitingForRelease else { return nil }
        if let singleKeyStartedAt {
            return Hold(deadline: singleKeyStartedAt + nanoseconds(rules.singleKeyHoldMS), pattern: .singleKeyHold)
        }
        guard rules.settlingEnabled, held.count >= rules.settlingKeyCount else { return nil }
        let starts = held.values.sorted()
        let span = rules.settlingKeyCount - 1
        for index in span..<starts.count where starts[index] - starts[index - span] <= nanoseconds(rules.settlingWindowMS) {
            return Hold(deadline: starts[index] + nanoseconds(rules.settlingHoldMS), pattern: .settling)
        }
        return nil
    }

    mutating func press(_ key: Int64, at time: UInt64, detecting: Bool) -> PawPattern? {
        singleKeyStartedAt = rules.singleKeyEnabled && detecting && !waitingForRelease && held.isEmpty ? time : nil
        // A fresh keydown replaces an older press if macOS withheld its release.
        held[key] = time
        guard detecting else {
            pause()
            return nil
        }
        guard !waitingForRelease else { return nil }
        if rules.landingEnabled {
            let window = nanoseconds(rules.landingWindowMS)
            if held.values.filter({ time - min(time, $0) <= window }).count >= rules.landingKeyCount { return .landing }
        }
        guard rules.crossingEnabled else { return nil }
        let crossingWindow = nanoseconds(rules.crossingWindowMS)
        if let firstStep, time - min(time, firstStep.startedAt) > crossingWindow {
            self.firstStep = nil
        }
        pendingSteps.removeAll { time - min(time, $0.startedAt) > crossingWindow }
        // Each paw gets its own pair even if the previous paw hasn't lifted yet.
        let paired = Set(pendingSteps.flatMap(\.keys))
        if !paired.contains(key),
           let previous = held.filter({ $0.key != key && !paired.contains($0.key) }).max(by: { $0.value < $1.value }),
           time - min(time, previous.value) <= nanoseconds(rules.crossingPairWindowMS) {
            pendingSteps.append(Step(keys: [previous.key, key], startedAt: time))
        }
        return nil
    }

    mutating func release(_ key: Int64, at time: UInt64, detecting: Bool) -> PawPattern? {
        guard held.removeValue(forKey: key) != nil else { return nil }
        cancelSingleKeyHold()
        if waitingForRelease {
            waitingForRelease = !held.isEmpty
            return nil
        }
        guard detecting, let index = pendingSteps.firstIndex(where: { $0.keys.contains(key) }) else { return nil }
        let step = pendingSteps.remove(at: index)
        guard time - min(time, step.startedAt) >= nanoseconds(rules.crossingOverlapMS) else { return nil }
        if let firstStep,
           max(step.startedAt, firstStep.startedAt) - min(step.startedAt, firstStep.startedAt) <= nanoseconds(rules.crossingWindowMS),
           firstStep.keys.isDisjoint(with: step.keys) {
            return .crossing
        }
        firstStep = step
        return nil
    }

    mutating func pause() {
        cancelSingleKeyHold()
        waitingForRelease = !held.isEmpty
        pendingSteps.removeAll()
        firstStep = nil
    }

    mutating func cancelSingleKeyHold() {
        singleKeyStartedAt = nil
    }

    private func nanoseconds(_ milliseconds: Int) -> UInt64 {
        UInt64(milliseconds) * 1_000_000
    }
}
