import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/services/html_preview_static_server.dart';

void main() {
  late Directory root;
  late HtmlPreviewStaticServer server;

  setUp(() {
    root = Directory.systemTemp.createTempSync('html_preview_server_');
    File(
      '${root.path}/index.html',
    ).writeAsStringSync('<!DOCTYPE html><html><body>sea</body></html>');
    File('${root.path}/app.js').writeAsStringSync('console.log(1);');
    server = HtmlPreviewStaticServer();
  });

  tearDown(() async {
    await server.stop();
    if (root.existsSync()) {
      root.deleteSync(recursive: true);
    }
  });

  test(
    'serves the project index and javascript with the right types',
    () async {
      final origin = await server.start(projectRoot: root.path);
      expect(origin.host, '127.0.0.1');
      expect(origin.port, greaterThan(0));

      final html = await _get(origin.replace(path: '/index.html'));
      expect(html.statusCode, 200);
      expect(html.contentType, contains('text/html'));
      expect(html.body, contains('sea'));

      final fromRoot = await _get(origin.replace(path: '/'));
      expect(fromRoot.body, contains('sea'));

      final js = await _get(origin.replace(path: '/app.js'));
      expect(js.statusCode, 200);
      expect(js.contentType, contains('javascript'));
      expect(js.body, contains('console.log'));
    },
  );

  test('rejects path traversal out of the project root', () async {
    final origin = await server.start(projectRoot: root.path);

    final response = await _get(
      Uri.parse('${origin.origin}/%2e%2e/%2e%2e/etc/passwd'),
    );

    expect(response.statusCode, 404);
    expect(response.body, isNot(contains('root:')));
  });

  test('does not serve dotfiles, keys, or node_modules', () async {
    File('${root.path}/.env').writeAsStringSync('SECRET=1');
    File('${root.path}/id_rsa').writeAsStringSync('key');
    Directory('${root.path}/node_modules/pkg').createSync(recursive: true);
    File(
      '${root.path}/node_modules/pkg/index.js',
    ).writeAsStringSync('export default 1');
    final origin = await server.start(projectRoot: root.path);

    expect((await _get(origin.replace(path: '/.env'))).statusCode, 404);
    expect((await _get(origin.replace(path: '/id_rsa'))).statusCode, 404);
    expect(
      (await _get(
        origin.replace(path: '/node_modules/pkg/index.js'),
      )).statusCode,
      404,
    );
  });

  test('isBlockedRelativePath covers secrets without starting a server', () {
    expect(HtmlPreviewStaticServer.isBlockedRelativePath('.env'), isTrue);
    expect(
      HtmlPreviewStaticServer.isBlockedRelativePath('.git/config'),
      isTrue,
    );
    expect(
      HtmlPreviewStaticServer.isBlockedRelativePath('node_modules/x.js'),
      isTrue,
    );
    expect(
      HtmlPreviewStaticServer.isBlockedRelativePath('index.html'),
      isFalse,
    );
    expect(HtmlPreviewStaticServer.isBlockedRelativePath('app.js'), isFalse);
  });
}

class _HttpBody {
  const _HttpBody({
    required this.statusCode,
    required this.contentType,
    required this.body,
  });

  final int statusCode;
  final String contentType;
  final String body;
}

Future<_HttpBody> _get(Uri url) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(url);
    final response = await request.close();
    final body = await utf8.decoder.bind(response).join();
    return _HttpBody(
      statusCode: response.statusCode,
      contentType: response.headers.contentType?.toString() ?? '',
      body: body,
    );
  } finally {
    client.close(force: true);
  }
}
