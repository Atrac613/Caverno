First, stop new writes to the affected shard.
Next, restore the latest verified snapshot.
The monitoring dashboard remains available throughout recovery.
Then, replay the signed journal from the snapshot boundary.
Finally, compare the restored row count with the signed manifest.
The recovery contact list is maintained in a separate system.
If verification fails, keep the shard read-only and preserve diagnostics.
