import Foundation

@main
enum WatchSnapshotCursorSmoke {
  static func main() throws {
    var cursor = WatchSnapshotCursor()
    let oldEight = try snapshot(source: "old", startedAt: 100, sequence: 8)
    let oldSeven = try snapshot(source: "old", startedAt: 100, sequence: 7)
    let newOne = try snapshot(source: "new", startedAt: 200, sequence: 1)
    let oldNine = try snapshot(source: "old", startedAt: 100, sequence: 9)
    let newTwo = try snapshot(source: "new", startedAt: 200, sequence: 2)

    precondition(cursor.accepts(oldEight))
    precondition(!cursor.accepts(oldSeven))
    precondition(cursor.accepts(newOne))
    precondition(!cursor.accepts(oldNine))
    precondition(cursor.accepts(newTwo))

    var legacyCursor = WatchSnapshotCursor()
    let legacyThree = try snapshot(source: "", startedAt: 0, sequence: 3)
    let legacyTwo = try snapshot(source: "", startedAt: 0, sequence: 2)
    precondition(legacyCursor.accepts(legacyThree))
    precondition(!legacyCursor.accepts(legacyTwo))
    precondition(!cursor.accepts(legacyThree))

    let collidingSource = try snapshot(
      source: "other",
      startedAt: 200,
      sequence: 3
    )
    precondition(!cursor.accepts(collidingSource))
    print("Watch snapshot restart ordering passed")
  }

  private static func snapshot(
    source: String,
    startedAt: Int64,
    sequence: Int
  ) throws -> WatchSnapshot {
    let json: [String: Any] = [
      "sourceInstanceId": source,
      "sourceStartedAtMicros": startedAt,
      "sequence": sequence,
      "generatedAt": "2026-09-04T12:00:00.000Z",
    ]
    let data = try JSONSerialization.data(withJSONObject: json)
    return try JSONDecoder().decode(WatchSnapshot.self, from: data)
  }
}
