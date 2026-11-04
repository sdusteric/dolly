import Foundation

/// Runs slow work off the main actor, one input at a time. While one runs, a new input replaces
/// any input still waiting, so a drag renders its newest step and skips the ones in between.
/// Every finished result is delivered unless `cancel()` came after it started.
@MainActor
public final class LatestOnly<Input: Sendable, Output: Sendable> {
    private let work: @Sendable (Input) async -> Output
    private let deliver: (Output) -> Void
    private var pending: Input?
    private var generation = 0
    public private(set) var isBusy = false

    public init(work: @escaping @Sendable (Input) async -> Output, deliver: @escaping (Output) -> Void) {
        self.work = work
        self.deliver = deliver
    }

    public func submit(_ input: Input) {
        if isBusy {
            pending = input
        } else {
            start(input)
        }
    }

    /// Drops the waiting input and the result of the one running.
    public func cancel() {
        generation += 1
        pending = nil
    }

    private func start(_ input: Input) {
        isBusy = true
        let started = generation
        let work = work
        Task { [weak self] in
            let output = await Task.detached { await work(input) }.value
            guard let self else { return }
            isBusy = false
            if started == generation { deliver(output) }
            if let next = pending {
                pending = nil
                start(next)
            }
        }
    }
}
