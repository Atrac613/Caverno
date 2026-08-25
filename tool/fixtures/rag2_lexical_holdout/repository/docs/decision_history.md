# Decision History

Riverpod Notifier was selected so feature state stays explicit and testable
without introducing a second state-management system.

MaterialPageRoute remains sufficient because navigation is deliberately small;
a router dependency was deferred until deep-link requirements justify it.

Hive conversation storage was retired after drift became the authoritative
transactional store. Approximate nearest-neighbor search was deferred until
corpus-scale measurements justify another dependency.
