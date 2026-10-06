import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/maintenance/domain/services/idle_maintenance_environment.dart';
import 'package:http/http.dart' as http;

class FarmIdleEnvironment implements IdleMaintenanceEnvironment {
  @override
  DateTime now() => DateTime(2026, 10, 4, 3);
  @override
  Duration idleFor() => const Duration(hours: 1);
  @override
  bool onAcPower() => true;
}

class FarmFixtureClient extends http.BaseClient {
  final http.Client _inner = http.Client();
  int successfulCalls = 0;
  final wireToolCalls = <Object?>[];
  final wireMessages = <Object?>[];
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = await request.finalize().toBytes();
    final text = utf8.decode(body);
    for (final forbidden in ['/Users/', 'Caverno agent guide', '.caverno/']) {
      if (text.contains(forbidden)) {
        throw StateError('Non-fixture HTTP payload');
      }
    }
    final forwarded = http.Request(request.method, request.url)
      ..headers.addAll(request.headers)
      ..bodyBytes = body;
    final response = await _inner.send(forwarded);
    final bytes = await response.stream.toBytes();
    if (response.statusCode == 200) {
      successfulCalls++;
      final decoded = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      for (final choice in decoded['choices'] as List<dynamic>) {
        final message = choice['message'] as Map<String, dynamic>;
        wireMessages.add(message['content']);
        wireToolCalls.addAll(message['tool_calls'] as List<dynamic>? ?? []);
      }
    }
    return http.StreamedResponse(
      Stream.value(bytes),
      response.statusCode,
      headers: response.headers,
      reasonPhrase: response.reasonPhrase,
      request: response.request,
    );
  }

  @override
  void close() => _inner.close();
}

Future<String> farmFixtureGit(String root, List<String> args) async {
  final result = await Process.run('git', args, workingDirectory: root);
  if (result.exitCode != 0) {
    throw StateError('Fixture Git failed: ${result.stderr}');
  }
  return result.stdout.toString().trim();
}
