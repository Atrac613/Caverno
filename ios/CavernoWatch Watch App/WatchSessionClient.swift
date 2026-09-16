import Combine
import Foundation
import WatchConnectivity
import WatchKit
import WidgetKit

/// The watch side of the bridge implemented by `WatchBridgePlugin` in
/// `ios/Runner/AppDelegate.swift`.
///
/// Holds the latest snapshot, sends commands, and collects the streamed answer
/// text. Everything published here is main-actor state driven by
/// WatchConnectivity callbacks, which arrive on a background queue.
@MainActor
final class WatchSessionClient: NSObject, ObservableObject {
  private struct PendingRemoteMessage {
    let content: String
    let isVoiceMode: Bool
    let hostId: String
    let projectId: String
    let conversationId: String
  }

  /// Key both sides use for the JSON payload.
  private static let payloadKey = "payload"

  @Published private(set) var snapshot: WatchSnapshot?
  @Published private(set) var isReachable = false
  @Published private(set) var hasActivated = false
  @Published private(set) var lastCommandError: String?
  @Published private(set) var lastCommandNotice: String?
  @Published private(set) var lastCommandResult: WatchCommandResult?
  @Published private var retryableRemoteMessage: PendingRemoteMessage?
  /// Text accumulated from stream chunks for the turn currently in flight.
  @Published private(set) var streamedText = ""
  /// Advances even when a final stream marker carries no new text.
  @Published private(set) var streamCompletionSequence = 0

  /// Snapshot ordering state for the current iPhone projection lifetime.
  ///
  /// WatchConnectivity makes no ordering guarantee across its transports: an
  /// application context can land after a newer `sendMessage`. Dropping lower
  /// sequences is what stops an old frame from resurrecting a resolved
  /// approval on screen.
  private var snapshotCursor = WatchSnapshotCursor()
  private var streamingTurnId: String?
  private var pendingRemoteMessages: [String: PendingRemoteMessage] = [:]

  private let session: WCSession? = WCSession.isSupported()
    ? WCSession.default : nil

  func activate() {
    guard let session else {
      hasActivated = true
      lastCommandError = "Watch connectivity is unavailable."
      return
    }
    session.delegate = self
    session.activate()
  }

  // MARK: - Commands

  @discardableResult
  func requestSnapshot() -> String? {
    send(.requestSnapshot)
  }

  @discardableResult
  func cancelStreaming() -> String? {
    guard let snapshot, !snapshot.isLocal else {
      return send(.cancelStreaming, payload: ["source": "local"])
    }
    guard let browser = snapshot.remoteBrowser, browser.canInput else {
      return failRemoteDestinationLocally()
    }
    var payload = browser.destination
    payload["source"] = "remote"
    return send(.cancelStreaming, payload: payload)
  }

  @discardableResult
  func selectConversation(id: String) -> String? {
    send(.selectConversation, payload: ["conversationId": id, "source": "local"])
  }

  @discardableResult
  func selectLocalSource() -> String? {
    send(.selectSource, payload: ["source": "local"])
  }

  @discardableResult
  func browseRemote(_ browser: WatchRemoteBrowser, projectId: String?, offset: Int = 0) -> String? {
    var payload = browser.destination
    payload["projectId"] = projectId
    payload["offset"] = offset
    return send(.browseRemote, payload: payload)
  }

  @discardableResult
  func selectRemoteConversation(_ browser: WatchRemoteBrowser, id: String) -> String? {
    var payload = browser.destination
    payload["conversationId"] = id
    return send(.selectRemoteConversation, payload: payload)
  }

  @discardableResult
  func sendMessage(_ content: String, isVoiceMode: Bool) -> String? {
    let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    streamedText = ""
    var payload: [String: Any]
    var pendingRemoteMessage: PendingRemoteMessage?
    if let snapshot, !snapshot.isLocal {
      guard let browser = snapshot.remoteBrowser, browser.canInput else {
        return failRemoteDestinationLocally()
      }
      payload = browser.destination
      payload["source"] = "remote"
      payload["content"] = trimmed
      payload["isVoiceMode"] = isVoiceMode
      if let projectId = browser.projectId,
        let conversationId = browser.conversationId
      {
        pendingRemoteMessage = PendingRemoteMessage(
          content: trimmed,
          isVoiceMode: isVoiceMode,
          hostId: browser.hostId,
          projectId: projectId,
          conversationId: conversationId
        )
      }
    } else {
      payload = [
        "content": trimmed,
        "isVoiceMode": isVoiceMode,
        "source": "local",
      ]
    }
    // Stamp the thread this text was composed against. When the phone is
    // unreachable the command falls back to transferUserInfo, which is
    // delivered eventually rather than promptly, and an unstamped message
    // would land in whichever thread is current by then.
    if let conversationId = snapshot?.conversationId {
      payload["conversationId"] = conversationId
    }
    let commandId = send(.sendMessage, payload: payload)
    if let commandId, let pendingRemoteMessage {
      pendingRemoteMessages[commandId] = pendingRemoteMessage
    }
    return commandId
  }

  var retryableMessagePreview: String? {
    guard let retry = retryableRemoteMessage,
      let browser = snapshot?.remoteBrowser,
      browser.canInput,
      browser.hostId == retry.hostId,
      browser.projectId == retry.projectId,
      browser.conversationId == retry.conversationId
    else { return nil }
    return retry.content
  }

  func retryRemoteMessage() {
    guard let retry = retryableRemoteMessage,
      retryableMessagePreview != nil
    else { return }
    retryableRemoteMessage = nil
    sendMessage(retry.content, isVoiceMode: retry.isVoiceMode)
  }

  private func failRemoteDestinationLocally() -> String {
    let commandId = UUID().uuidString
    failLocally(
      id: commandId,
      code: "destination_changed",
      message: "The remote thread changed. Open it again."
    )
    return commandId
  }

  /// Answers a goal awaiting confirmation.
  ///
  /// Stamped with the thread the decision was made against, for the reason
  /// `sendMessage` is: an unstamped command that falls back to
  /// `transferUserInfo` would close whichever goal is current when it lands.
  @discardableResult
  func resolveGoal(completed: Bool) -> String? {
    var payload: [String: Any] = ["completed": completed, "source": snapshot?.transcriptSource ?? "local"]
    if let conversationId = snapshot?.conversationId {
      payload["conversationId"] = conversationId
    }
    return send(.resolveGoal, payload: payload)
  }

  @discardableResult
  func resolveApproval(id: String, approved: Bool) -> String? {
    send(
      .resolveApproval,
      payload: ["approvalId": id, "approved": approved]
    )
  }

  @discardableResult
  func resolveQuestion(id: String, selectedOptionIds: [String]) -> String? {
    send(
      .resolveQuestion,
      payload: ["questionId": id, "selectedOptionIds": selectedOptionIds]
    )
  }

  @discardableResult
  func cancelQuestion(id: String) -> String? {
    send(.resolveQuestion, payload: ["questionId": id, "cancelled": true])
  }

  @discardableResult
  private func send(
    _ type: WatchCommandType,
    payload: [String: Any] = [:]
  ) -> String? {
    lastCommandError = nil
    lastCommandNotice = nil
    lastCommandResult = nil
    let commandId = UUID().uuidString
    guard let session else {
      failLocally(
        id: commandId,
        code: "connectivity_unavailable",
        message: "Watch connectivity is unavailable."
      )
      return commandId
    }
    guard session.activationState == .activated else {
      failLocally(
        id: commandId,
        code: "connection_starting",
        message: "The iPhone connection is still starting. Try again."
      )
      return commandId
    }
    let body: [String: Any] = [
      "type": type.rawValue,
      "id": commandId,
      "payload": payload,
    ]
    guard
      let data = try? JSONSerialization.data(withJSONObject: body),
      let json = String(data: data, encoding: .utf8)
    else {
      failLocally(
        id: commandId,
        code: "encoding_failed",
        message: "The command could not be encoded."
      )
      return commandId
    }

    if session.isReachable {
      session.sendMessage(
        [Self.payloadKey: json],
        replyHandler: nil,
        errorHandler: { [weak self] error in
          Task { @MainActor in
            let result = WatchCommandResult(
              ok: false,
              id: commandId,
              code: "transport_error",
              message: error.localizedDescription
            )
            self?.lastCommandResult = result
            self?.lastCommandError = error.localizedDescription
          }
        }
      )
    } else {
      // Wakes the iPhone app in the background and is delivered in order.
      // Slower than sendMessage, but it is the difference between a command
      // that lands and one that is silently dropped when the phone is asleep.
      session.transferUserInfo([Self.payloadKey: json])
      lastCommandNotice = "Queued until the iPhone reconnects."
    }
    return commandId
  }

  private func failLocally(id: String, code: String, message: String) {
    lastCommandResult = WatchCommandResult(
      ok: false,
      id: id,
      code: code,
      message: message
    )
    lastCommandError = message
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
      if let id = result.id,
        let pending = pendingRemoteMessages.removeValue(forKey: id)
      {
        if result.code == "remote_reconnected" {
          retryableRemoteMessage = pending
        } else if result.ok {
          retryableRemoteMessage = nil
        }
      }
      lastCommandResult = result
      lastCommandNotice = result.ok ? result.message : nil
      lastCommandError = result.ok ? nil : result.message
      return
    }
  }

  private func apply(_ next: WatchSnapshot) {
    guard snapshotCursor.accepts(next) else { return }
    let wasWaiting = snapshot?.needsAttention ?? false
    if snapshot?.transcriptIdentity != next.transcriptIdentity {
      streamedText = ""
      streamingTurnId = nil
    }
    snapshot = next
    if next.status != .streaming {
      streamingTurnId = nil
    }
    // Tap the wrist only on the transition into a blocked state, so a burst of
    // snapshots for one approval does not buzz repeatedly.
    if next.needsAttention && !wasWaiting {
      WKInterfaceDevice.current().play(.notification)
    }
    publishGlance(next)
  }

  /// Mirrors the little the Smart Stack shows into the shared App Group.
  ///
  /// Only counts and a status word: a widget renders without anyone opening
  /// anything, so conversation text has no business there. The store reports
  /// whether the value actually changed, and the timeline is reloaded only
  /// then — WidgetKit budget is finite and a re-render of the same glance
  /// spends it for nothing.
  private func publishGlance(_ snapshot: WatchSnapshot) {
    let glance = WatchGlance(
      status: snapshot.status.rawValue,
      busyThreadCount: snapshot.busyThreadCount,
      needsAttention: snapshot.needsAttention,
      updatedAt: Date()
    )
    if WatchGlanceStore.save(glance) {
      WidgetCenter.shared.reloadTimelines(ofKind: WatchGlanceStore.widgetKind)
    }
  }

  private func apply(_ chunk: WatchStreamChunk) {
    guard snapshot?.isLocal != false else { return }
    if streamingTurnId != chunk.turnId {
      streamingTurnId = chunk.turnId
      streamedText = ""
    }
    streamedText += chunk.text
    if chunk.isFinal {
      streamingTurnId = nil
      streamCompletionSequence += 1
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
      guard let self else { return }
      self.hasActivated = true
      self.isReachable = activationState == .activated && reachable
      if activationState == .activated {
        self.requestSnapshot()
      } else if let error {
        self.lastCommandError = error.localizedDescription
      }
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
