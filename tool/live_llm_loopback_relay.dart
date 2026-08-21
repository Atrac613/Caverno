import 'dart:async';
import 'dart:io';

Future<void> main(List<String> args) async {
  final options = _RelayOptions.parse(args);
  if (options == null) {
    stderr.writeln(
      'Usage: dart tool/live_llm_loopback_relay.dart '
      '--base-url URL --ready-file PATH',
    );
    exitCode = 64;
    return;
  }

  final origin = Uri.tryParse(options.baseUrl);
  if (origin == null ||
      origin.scheme != 'http' ||
      origin.host.isEmpty ||
      origin.hasFragment ||
      origin.userInfo.isNotEmpty) {
    stderr.writeln(
      'The loopback relay requires an HTTP base URL without credentials or a fragment.',
    );
    exitCode = 64;
    return;
  }
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final activeSockets = <Socket>{};
  final shutdown = Completer<void>();
  var shuttingDown = false;

  Future<void> stop() async {
    if (shuttingDown) {
      return;
    }
    shuttingDown = true;
    await server.close();
    for (final socket in activeSockets.toList(growable: false)) {
      socket.destroy();
    }
    if (!shutdown.isCompleted) {
      shutdown.complete();
    }
  }

  final signalSubscriptions = <StreamSubscription<ProcessSignal>>[
    ProcessSignal.sigint.watch().listen((_) => unawaited(stop())),
    ProcessSignal.sigterm.watch().listen((_) => unawaited(stop())),
  ];

  // The signal watchers hold the event loop open, so a bare `return` leaves the
  // process alive with nothing to do. The wrapper would then poll for a ready
  // file that is never coming and report a timeout, burying the real reason
  // under the wrong headline.
  Future<void> shutDownAndDetach() async {
    await stop();
    for (final subscription in signalSubscriptions) {
      await subscription.cancel();
    }
  }

  server.listen((client) async {
    Socket? upstream;
    activeSockets.add(client);

    void closePair() {
      activeSockets.remove(client);
      client.destroy();
      if (upstream != null) {
        activeSockets.remove(upstream);
        upstream.destroy();
      }
    }

    try {
      final connectedUpstream = await Socket.connect(origin.host, origin.port);
      upstream = connectedUpstream;
      activeSockets.add(connectedUpstream);
      client.listen(
        connectedUpstream.add,
        onError: (_) => closePair(),
        onDone: () => connectedUpstream.close(),
        cancelOnError: true,
      );
      connectedUpstream.listen(
        client.add,
        onError: (_) => closePair(),
        onDone: () => client.close(),
        cancelOnError: true,
      );
    } on Object catch (error) {
      stderr.writeln('Loopback relay connection failed: $error');
      closePair();
    }
  });

  // Reach upstream once before claiming to be ready.
  //
  // Binding loopback proves nothing about the origin: without this the relay
  // announces itself, the child's requests all die as "connection reset by
  // peer", and the one line saying why sits in a log the wrapper deletes on
  // exit. Failing here instead turns an unreachable origin into a single
  // legible error before any work is attempted.
  try {
    final preflight = await Socket.connect(
      origin.host,
      origin.port,
      timeout: const Duration(seconds: 10),
    );
    preflight.destroy();
  } on SocketException catch (error) {
    stderr.writeln(
      'The loopback relay cannot reach ${origin.host}:${origin.port}: $error',
    );
    if (Platform.isMacOS && error.osError?.errorCode == 65) {
      // EHOSTUNREACH from a signed binary that is not Apple's is what macOS
      // Local Network Privacy looks like: the connection is reported
      // unreachable rather than refused, and no prompt is shown for a CLI.
      // curl reaching the same host proves the route exists.
      stderr.writeln(
        'On macOS this is usually Local Network Privacy denying the dart '
        'binary, not a routing problem. Check that curl reaches the same '
        'host, then enable dart under System Settings > Privacy & Security > '
        'Local Network.',
      );
    }
    await shutDownAndDetach();
    exitCode = 69;
    return;
  }

  final effectiveBaseUrl = origin
      .replace(host: InternetAddress.loopbackIPv4.address, port: server.port)
      .toString();
  final readyFile = File(options.readyFile);
  readyFile.parent.createSync(recursive: true);
  readyFile.writeAsStringSync('$effectiveBaseUrl\n', flush: true);
  stdout.writeln(
    'Live LLM loopback relay ready: $effectiveBaseUrl -> ${options.baseUrl}',
  );

  await shutdown.future;
  for (final subscription in signalSubscriptions) {
    await subscription.cancel();
  }
}

final class _RelayOptions {
  const _RelayOptions({required this.baseUrl, required this.readyFile});

  final String baseUrl;
  final String readyFile;

  static _RelayOptions? parse(List<String> args) {
    String? baseUrl;
    String? readyFile;
    for (var index = 0; index < args.length; index += 1) {
      final argument = args[index];
      if (index + 1 >= args.length) {
        return null;
      }
      switch (argument) {
        case '--base-url':
          baseUrl = args[++index];
        case '--ready-file':
          readyFile = args[++index];
        default:
          return null;
      }
    }
    if (baseUrl == null ||
        baseUrl.isEmpty ||
        readyFile == null ||
        readyFile.isEmpty) {
      return null;
    }
    return _RelayOptions(baseUrl: baseUrl, readyFile: readyFile);
  }
}
