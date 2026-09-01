import Combine
import Foundation
import WatchConnectivity
import WatchKit

/// The watch side of the bridge implemented by `WatchBridgePlugin` in
/// `ios/Runner/AppDelegate.swift`.
///
/// Holds the latest snapshot, sends commands, and collects the streamed answer
/// text. Everything published here is main-actor state driven by
/// WatchConnectivity callbacks, which arrive on a background queue.
@MainActor
final class WatchSessionClient: NSObject, ObservableObject {
  /// Key both sides use for the JSON payload.
  private static let payloadKey = "payload"

  @Published private(set) var snapshot: WatchSnapshot?
  @Published private(set) var isReachable = false
  @Published private(set) var lastCommandError: String?
  /// Text accumulated from stream chunks for the turn currently in flight.
  @Published private(set) var streamedText = ""

  /// Highest snapshot sequence rendered so far.
  ///
  /// WatchConnectivity makes no ordering guarantee across its transports: an
  /// application context can land after a newer `sendMessage`. Dropping lower
  /// sequences is what stops an old frame from resurrecting a resolved
  /// approval on screen.
  private var lastSequence = 0
  private var streamingTurnId: String?

  private let session: WCSession? = WCSession.isSupported()
    ? WCSession.default : nil

  func activate() {
    guard let session else { return }
    session.delegate = self
    session.activate()
  }

  // MARK: - Commands

  func requestSnapshot() {
    send(.requestSnapshot)
  }

  func cancelStreaming() {
    send(.cancelStreaming)
  }

  func sendMessage(_ content: String, isVoiceMode: Bool) {
    let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    streamedText = ""
    var payload: [String: Any] = [
      "content": trimmed,
      "isVoiceMode": isVoiceMode,
    ]
    // Stamp the thread this text was composed against. When the phone is
    // unreachable the command falls back to transferUserInfo, which is
    // delivered eventually rather than promptly, and an unstamped message
    // would land in whichever thread is current by then.
    if let conversationId = snapshot?.conversationId {
      payload["conversationId"] = conversationId
    }
    send(.sendMessage, payload: payload)
  }

  func resolveApproval(id: String, approved: Bool) {
    send(.resolveApproval, payload: ["approvalId": id, "approved": approved])
    WKInterfaceDevice.current().play(approved ? .success : .click)
  }

  func resolveQuestion(id: String, selectedOptionIds: [String]) {
    send(
      .resolveQuestion,
      payload: ["questionId": id, "selectedOptionIds": selectedOptionIds]
    )
    WKInterfaceDevice.current().play(.success)
  }

  func cancelQuestion(id: String) {
    send(.resolveQuestion, payload: ["questionId": id, "cancelled": true])
  }

  private func send(
    _ type: WatchCommandType,
    payload: [String: Any] = [:]
  ) {
    guard let session, session.activationState == .activated else { return }
    let body: [String: Any] = [
      "type": type.rawValue,
      "id": UUID().uuidString,
      "payload": payload,
    ]
    guard
      let data = try? JSONSerialization.data(withJSONObject: body),
      let json = String(data: data, encoding: .utf8)
    else { return }

    if session.isReachable {
      session.sendMessage(
        [Self.payloadKey: json],
        replyHandler: nil,
        errorHandler: { [weak self] error in
          Task { @MainActor in
            self?.lastCommandError = error.localizedDescription
          }
        }
      )
    } else {
      // Wakes the iPhone app in the background and is delivered in order.
      // Slower than sendMessage, but it is the difference between a command
      // that lands and one that is silently dropped when the phone is asleep.
      session.transferUserInfo([Self.payloadKey: json])
    }
  }

  // MARK: - Inbound

  fileprivate func handle(payload: String) {
    guard let data = payload.data(using: .utf8) else { return }
    let decoder = JSONDecoder()

    if let snapshot = try? decoder.decode(WatchSnapshot.self, from: data),
      snapshot.sequence > 0
    {
      apply(snapshot)
      return
    }
    if let chunk = try? decoder.decode(WatchStreamChunk.self, from: data) {
      apply(chunk)
      return
    }
    if let result = try? decoder.decode(WatchCommandResult.self, from: data) {
      lastCommandError = result.ok ? nil : result.message
      return
    }
  }

  private func apply(_ next: WatchSnapshot) {
    guard next.sequence > lastSequence else { return }
    let wasWaiting = snapshot?.needsAttention ?? false
    lastSequence = next.sequence
    snapshot = next
    if next.status != .streaming {
      streamingTurnId = nil
    }
    // Tap the wrist only on the transition into a blocked state, so a burst of
    // snapshots for one approval does not buzz repeatedly.
    if next.needsAttention && !wasWaiting {
      WKInterfaceDevice.current().play(.notification)
    }
  }

  private func apply(_ chunk: WatchStreamChunk) {
    if streamingTurnId != chunk.turnId {
      streamingTurnId = chunk.turnId
      streamedText = ""
    }
    streamedText += chunk.text
    if chunk.isFinal {
      streamingTurnId = nil
    }
  }
}

extension WatchSessionClient: WCSessionDelegate {
  nonisolated func session(
    _ session: WCSession,
    activationDidCompleteWith activationState: WCSessionActivationState,
    error: Error?
  ) {
    let reachable = session.isReachable
    Task { @MainActor [weak self] in
      self?.isReachable = reachable
      self?.requestSnapshot()
    }
  }

  nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
    let reachable = session.isReachable
    Task { @MainActor [weak self] in
      self?.isReachable = reachable
      if reachable {
        // The phone may have moved on while the watch was out of range.
        self?.requestSnapshot()
      }
    }
  }

  nonisolated func session(
    _ session: WCSession,
    didReceiveMessage message: [String: Any]
  ) {
    forward(message)
  }

  nonisolated func session(
    _ session: WCSession,
    didReceiveApplicationContext applicationContext: [String: Any]
  ) {
    forward(applicationContext)
  }

  nonisolated func session(
    _ session: WCSession,
    didReceiveUserInfo userInfo: [String: Any]
  ) {
    forward(userInfo)
  }

  private nonisolated func forward(_ message: [String: Any]) {
    guard let payload = message["payload"] as? String else { return }
    Task { @MainActor [weak self] in
      self?.handle(payload: payload)
    }
  }
}
