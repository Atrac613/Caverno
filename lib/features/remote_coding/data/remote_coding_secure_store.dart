import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class RemoteCodingSecureStore {
  Future<void> write({required String key, required String value});

  Future<String?> read({required String key});

  Future<void> delete({required String key});
}

final class FlutterRemoteCodingSecureStore implements RemoteCodingSecureStore {
  const FlutterRemoteCodingSecureStore({
    this.storage = const FlutterSecureStorage(),
  });

  final FlutterSecureStorage storage;

  @override
  Future<void> write({required String key, required String value}) {
    return storage.write(key: key, value: value);
  }

  @override
  Future<String?> read({required String key}) {
    return storage.read(key: key);
  }

  @override
  Future<void> delete({required String key}) {
    return storage.delete(key: key);
  }
}
