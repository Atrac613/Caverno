import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// One server slot reported by llama.cpp `GET /slots`.
class ServerSlot {
  const ServerSlot({required this.id, required this.isProcessing});

  final int id;

  /// Whether the slot is currently generating. Idle slots are preferred when
  /// assigning a conversation or Best-of-N candidate.
  final bool isProcessing;
}

/// Result of probing `GET /slots`: whether the endpoint supports slot
/// monitoring (`--parallel N` with slots enabled) and the slots it reported.
///
/// `supported` is false whenever the endpoint cannot be used for slot pinning —
/// a non-2xx response (`--no-slots` / older servers return 501), a malformed
/// body, or an empty slot list — so callers transparently fall back to
/// sequential single-slot execution.
class SlotInventory {
  const SlotInventory({required this.supported, required this.slots});

  const SlotInventory.unsupported() : supported = false, slots = const [];

  final bool supported;
  final List<ServerSlot> slots;

  int get slotCount => slots.length;

  /// True when the server exposes more than one slot, i.e. it was launched with
  /// `--parallel N` (N > 1) and candidates can run concurrently.
  bool get hasParallelSlots => slots.length > 1;

  List<int> get slotIds => [for (final slot in slots) slot.id]..sort();

  List<int> get idleSlotIds => [
    for (final slot in slots)
      if (!slot.isProcessing) slot.id,
  ]..sort();

  factory SlotInventory.fromJson(Object? json) {
    if (json is! List) return const SlotInventory.unsupported();
    final slots = <ServerSlot>[];
    for (final item in json) {
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item);
      final id = _asInt(map['id']);
      if (id == null) continue;
      slots.add(ServerSlot(id: id, isProcessing: _readProcessing(map)));
    }
    if (slots.isEmpty) return const SlotInventory.unsupported();
    return SlotInventory(supported: true, slots: slots);
  }

  static bool _readProcessing(Map<String, dynamic> slot) {
    final isProcessing = slot['is_processing'];
    if (isProcessing is bool) return isProcessing;
    // llama.cpp slot state: 0 == idle, anything else == busy.
    final state = _asInt(slot['state']);
    if (state != null) return state != 0;
    return false;
  }
}

/// LL20 slot discovery: probes a llama.cpp / LM Studio endpoint's `GET /slots`
/// so the parallel executor can decide whether to pin candidates to distinct
/// slots or fall back to sequential execution.
class LlamaCppSlotDiscovery {
  LlamaCppSlotDiscovery({
    required String baseUrl,
    required String apiKey,
    http.Client? client,
    Duration timeout = const Duration(seconds: 8),
  }) : _baseUrl = baseUrl,
       _apiKey = apiKey,
       _client = client ?? http.Client(),
       _timeout = timeout;

  final String _baseUrl;
  final String _apiKey;
  final http.Client _client;
  final Duration _timeout;

  /// `{nativeRoot}/slots`. The slots endpoint lives at the server root, not
  /// under the OpenAI `/v1` prefix, so the `/v1` suffix is stripped.
  Uri get slotsUri => Uri.parse('${_nativeRoot()}/slots');

  Future<SlotInventory> discover() async {
    try {
      final response = await _client
          .get(slotsUri, headers: _headers())
          .timeout(_timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return const SlotInventory.unsupported();
      }
      return SlotInventory.fromJson(jsonDecode(response.body));
    } on FormatException {
      return const SlotInventory.unsupported();
    } on TimeoutException {
      return const SlotInventory.unsupported();
    } on Object {
      return const SlotInventory.unsupported();
    }
  }

  String _nativeRoot() {
    final normalized = _baseUrl.replaceFirst(RegExp(r'/+$'), '');
    if (normalized.endsWith('/v1')) {
      return normalized.substring(0, normalized.length - '/v1'.length);
    }
    return normalized;
  }

  Map<String, String> _headers() {
    final headers = <String, String>{'Accept': 'application/json'};
    final apiKey = _apiKey.trim();
    if (apiKey.isNotEmpty) {
      headers['Authorization'] = 'Bearer $apiKey';
    }
    return headers;
  }

  void close() => _client.close();
}

int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}
