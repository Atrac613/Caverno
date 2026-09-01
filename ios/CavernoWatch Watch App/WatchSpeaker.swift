import AVFoundation
import Combine
import Foundation

/// Reads streamed answer text aloud on the watch.
///
/// Synthesis is local rather than piped from the phone on purpose: shipping
/// VOICEVOX or Whisper audio over WatchConnectivity adds a file transfer in
/// each direction, and the latency shows up exactly where it hurts most — the
/// gap between speaking and being answered. Remote synthesis stays an option
/// for later; this makes the loop usable now.
@MainActor
final class WatchSpeaker: NSObject, ObservableObject {
  @Published private(set) var isSpeaking = false
  @Published var isEnabled = true

  private let synthesizer = AVSpeechSynthesizer()
  /// Text already handed to the synthesizer, so re-renders of a growing stream
  /// only enqueue the new tail.
  private var spokenPrefix = ""

  override init() {
    super.init()
    synthesizer.delegate = self
  }

  /// Speaks whatever part of [text] has not been spoken yet.
  ///
  /// Only complete sentences are enqueued: handing the synthesizer a partial
  /// clause makes it stop mid-phrase and resume with the wrong intonation.
  func speakIncremental(_ text: String) {
    guard isEnabled else { return }
    guard text.hasPrefix(spokenPrefix) else {
      // The stream restarted (a new turn); start over.
      reset()
      speakIncremental(text)
      return
    }
    let tail = String(text.dropFirst(spokenPrefix.count))
    guard let boundary = lastSentenceBoundary(in: tail) else { return }
    let sentence = String(tail[..<boundary]).trimmingCharacters(
      in: .whitespacesAndNewlines)
    spokenPrefix = String(text[..<text.index(
      text.startIndex, offsetBy: spokenPrefix.count + tail.distance(
        from: tail.startIndex, to: boundary))])
    guard !sentence.isEmpty else { return }
    enqueue(sentence)
  }

  func speakAll(_ text: String) {
    guard isEnabled else { return }
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    reset()
    spokenPrefix = text
    enqueue(trimmed)
  }

  func stop() {
    synthesizer.stopSpeaking(at: .immediate)
    isSpeaking = false
  }

  func reset() {
    stop()
    spokenPrefix = ""
  }

  private func enqueue(_ sentence: String) {
    configureAudioSession()
    let utterance = AVSpeechUtterance(string: sentence)
    utterance.rate = AVSpeechUtteranceDefaultSpeechRate
    synthesizer.speak(utterance)
    isSpeaking = true
  }

  private func configureAudioSession() {
    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playback, mode: .spokenAudio)
      try session.setActive(true)
    } catch {
      // Speech is an enhancement; a busy audio session should not take the
      // rest of the view down with it.
      NSLog("WatchSpeaker: audio session unavailable: \(error)")
    }
  }

  /// Index just past the last sentence terminator, covering Japanese
  /// punctuation as well since the app is used in both languages.
  private func lastSentenceBoundary(in text: String) -> String.Index? {
    let terminators: Set<Character> = [".", "!", "?", "。", "！", "？", "\n"]
    guard let index = text.lastIndex(where: { terminators.contains($0) }) else {
      return nil
    }
    return text.index(after: index)
  }
}

extension WatchSpeaker: AVSpeechSynthesizerDelegate {
  nonisolated func speechSynthesizer(
    _ synthesizer: AVSpeechSynthesizer,
    didFinish utterance: AVSpeechUtterance
  ) {
    Task { @MainActor [weak self] in
      guard let self, !self.synthesizer.isSpeaking else { return }
      self.isSpeaking = false
    }
  }

  nonisolated func speechSynthesizer(
    _ synthesizer: AVSpeechSynthesizer,
    didCancel utterance: AVSpeechUtterance
  ) {
    Task { @MainActor [weak self] in
      self?.isSpeaking = false
    }
  }
}
