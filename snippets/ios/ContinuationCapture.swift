import Foundation

/// Defensive resume pattern for `CheckedContinuation` callbacks.
///
/// In a `@MainActor`-isolated repository that wraps async I/O, multiple
/// resolution sites (success ack, failure ack, timeout, replacement) all
/// race for the same pending continuation reference. The naive pattern…
///
///     pendingAck?.resume(returning: ok)
///     pendingAck = nil
///
/// …is correct in isolation, but if any reentrancy slips into the resume
/// path (a delegate, an observer, an actor hop) the property is still
/// non-nil between the two statements and a second site can resume the
/// same continuation, which crashes the process with `SWIFT TASK
/// CONTINUATION MISUSE`.
///
/// Capturing the continuation locally and nilling the property *before*
/// resuming makes the property an atomic ownership transfer: at most one
/// caller observes a non-nil continuation, ever.
@MainActor
final class AckCoordinator {

    private var pendingAck: CheckedContinuation<Bool, Never>?
    private let send: (Data) -> Void

    init(send: @escaping (Data) -> Void) {
        self.send = send
    }

    /// Sends a packet and awaits its ack. Cancellation of an existing
    /// pending ack is part of the contract — the caller can trigger
    /// `cancelPending()` to clear the slate before queuing a new request.
    func sendAndAwait(_ packet: Data) async -> Bool {
        await withCheckedContinuation { continuation in
            pendingAck = continuation
            send(packet)
        }
    }

    /// Resolve the pending ack with a success / failure result.
    func resolve(_ success: Bool) {
        let cont = pendingAck
        pendingAck = nil
        cont?.resume(returning: success)
    }

    /// Cancel the in-flight ack so a new request can take its place.
    func cancelPending() {
        let cont = pendingAck
        pendingAck = nil
        cont?.resume(returning: false)
    }
}
