/// Narrow BLE connection effect boundary used by owner-aware coordination.
abstract interface class BleConnectionEffectPort {
  Future<void> connect(String deviceId);

  Future<void> disconnect(String deviceId);

  String getConnectionState(String deviceId);
}
