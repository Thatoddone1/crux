//
//  VerificationModel.swift
//  Crux
//

import Foundation
import MatrixRustSDK

/// Runs one device- or user-verification ceremony (SAS emoji comparison) and tracks its state for the UI.
@Observable
final class VerificationModel {
    enum Phase {
        case idle
        case requesting
        /// Another one of our devices (or another user) asked to verify us; shown before we've accepted.
        case incomingRequest(SessionVerificationRequestDetails)
        case waitingForOtherParty
        case comparing(emojis: [Emoji])
        case finished
        case cancelled
        case failed
    }

    struct Emoji: Identifiable {
        let id = UUID()
        let symbol: String
        let name: String
    }

    private(set) var phase: Phase = .idle

    /// Whether *this device* is cross-signing verified. Check this before offering a "Verify"
    /// button — a device that's already verified has nothing to gain from running the ceremony
    /// again (and Element/other clients may just refuse a redundant request).
    private(set) var deviceVerificationState: VerificationState = .unknown
    var isDeviceVerified: Bool { deviceVerificationState == .verified }

    private let client: Client
    private var controller: SessionVerificationController?
    private var stateHandle: TaskHandle?

    init(client: Client) {
        self.client = client
    }

    // MARK: - Lifecycle

    /// Registers this device to hear incoming verification requests (e.g. from a fresh login
    /// elsewhere) and starts tracking whether this device is verified. Call once, at sign-in —
    /// a request that arrives before this runs is missed.
    func start() async {
        guard controller == nil else { return }

        let encryption = client.encryption()
        deviceVerificationState = encryption.verificationState()
        stateHandle = encryption.verificationStateListener(listener: VerificationStateBridge { state in
            Task { @MainActor [weak self] in self?.deviceVerificationState = state }
        })

        _ = try? await makeController()
    }

    // MARK: - start verification from this device

    /// Verifies this device against one of the user's other signed-in devices.
    func requestDeviceVerification() async throws {
        let controller = try await makeController()
        phase = .requesting
        try await controller.requestDeviceVerification()
    }

    /// Verifies another user's cross-signing identity, e.g. from their profile in a room.
    func requestUserVerification(userId: String) async throws {
        let controller = try await makeController()
        phase = .requesting
        try await controller.requestUserVerification(userId: userId)
    }

    // MARK: - Responding to an incoming request

    /// Accepts a request that arrived via `didReceiveVerificationRequest` (reflected in `phase`)
    /// and immediately moves it into the emoji-comparison flow.
    func accept() async throws {
        try await controller?.acceptVerificationRequest()
        try await controller?.startSasVerification()
    }

    /// Confirms the emoji matched on both sides.
    func approve() async throws {
        try await controller?.approveVerification()
    }

    /// Rejects the emoji comparison because they didn't match.
    func decline() async throws {
        try await controller?.declineVerification()
    }

    func cancel() async throws {
        try await controller?.cancelVerification()
    }

    // MARK: - Private

    /// Returns the existing controller, or fetches one and wires up its delegate the first time.
    private func makeController() async throws -> SessionVerificationController {
        if let controller { return controller }
        let controller = try await client.getSessionVerificationController()
        controller.setDelegate(delegate: VerificationBridge { event in
            Task { @MainActor [weak self] in self?.apply(event) }
        })
        self.controller = controller
        return controller
    }

    private func apply(_ event: VerificationBridge.Event) {
        switch event {
        case .receivedRequest(let details):
            phase = .incomingRequest(details)
            // `acceptVerificationRequest()` only works on a request the controller has
            // acknowledged as "active" first — required per-request bookkeeping, not a choice.
            Task {
                try? await controller?.acknowledgeVerificationRequest(senderId: details.senderProfile.userId,
                                                                       flowId: details.flowId)
            }
        case .acceptedRequest:
            // The other party accepted a request *we* sent; drive our side into SAS too.
            phase = .waitingForOtherParty
            Task { try? await controller?.startSasVerification() }
        case .startedSas: phase = .waitingForOtherParty
        case .receivedData(.emojis(let emojis, _)):
            phase = .comparing(emojis: emojis.map { Emoji(symbol: $0.symbol(), name: $0.description()) })
        case .receivedData(.decimals):
            // Crux only implements the emoji flow; bail out rather than get stuck.
            phase = .failed
        case .failed: phase = .failed
        case .cancelled: phase = .cancelled
        case .finished: phase = .finished
        }
    }
}

/// Forwards the SDK's verification-ceremony callbacks from its background threads.
private nonisolated final class VerificationBridge: SessionVerificationControllerDelegate {
    enum Event {
        case receivedRequest(SessionVerificationRequestDetails)
        case acceptedRequest
        case startedSas
        case receivedData(SessionVerificationData)
        case failed
        case cancelled
        case finished
    }

    private let handler: @Sendable (Event) -> Void

    init(_ handler: @escaping @Sendable (Event) -> Void) {
        self.handler = handler
    }

    func didReceiveVerificationRequest(details: SessionVerificationRequestDetails) { handler(.receivedRequest(details)) }
    func didAcceptVerificationRequest() { handler(.acceptedRequest) }
    func didStartSasVerification() { handler(.startedSas) }
    func didReceiveVerificationData(data: SessionVerificationData) { handler(.receivedData(data)) }
    func didFail() { handler(.failed) }
    func didCancel() { handler(.cancelled) }
    func didFinish() { handler(.finished) }
}

/// Forwards this device's verification-state changes from the SDK's background threads.
private nonisolated final class VerificationStateBridge: VerificationStateListener {
    private let handler: @Sendable (VerificationState) -> Void

    init(_ handler: @escaping @Sendable (VerificationState) -> Void) {
        self.handler = handler
    }

    func onUpdate(status: VerificationState) {
        handler(status)
    }
}
