import SwiftUI

@main
struct CavernoWatchApp: App {
  @StateObject private var client = WatchSessionClient()
  @StateObject private var speaker = WatchSpeaker()

  var body: some Scene {
    WindowGroup {
      ContentView()
        .environmentObject(client)
        .environmentObject(speaker)
        // Keep this subscription above navigation: changing source must stop
        // speech even while the transcript is covered by the project picker.
        .onReceive(client.$snapshot.map { $0?.transcriptIdentity }.removeDuplicates()) { _ in
          speaker.reset()
        }
        .task { client.activate() }
    }
  }
}
