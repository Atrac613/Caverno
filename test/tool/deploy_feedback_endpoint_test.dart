import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('feedback endpoint deploy helper', () {
    test('redacts sensitive values before storing feedback payloads', () async {
      final directory = Directory.systemTemp.createTempSync(
        'feedback-endpoint-redaction-',
      );
      addTearDown(() => directory.deleteSync(recursive: true));

      final lambdaSource = _extractLambdaSource(
        File('tool/deploy_feedback_endpoint.sh').readAsStringSync(),
      );
      final lambdaFile = File('${directory.path}/lambda_function.py')
        ..writeAsStringSync(lambdaSource);
      final harnessFile = File('${directory.path}/run_lambda_test.py')
        ..writeAsStringSync(_pythonHarness(lambdaFile.path));

      final result = await Process.run('python3', [harnessFile.path]);

      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect(result.stdout, contains('stored key: feedback/'));
    });
  });
}

String _extractLambdaSource(String script) {
  const startMarker = 'cat >"\$LAMBDA_SRC" <<\'PY\'\n';
  const endMarker = '\nPY\n\n(\n  cd "\$TMP_DIR"';
  final start = script.indexOf(startMarker);
  final end = script.indexOf(endMarker, start + startMarker.length);
  if (start == -1 || end == -1) {
    throw StateError('Could not locate embedded Lambda source.');
  }
  return script.substring(start + startMarker.length, end);
}

String _pythonHarness(String lambdaPath) {
  final encodedPath = jsonEncode(lambdaPath);
  return '''
import base64
import gzip
import importlib.util
import json
import os
import sys
import types


class FakeS3:
    def __init__(self):
        self.objects = []

    def put_object(self, **kwargs):
        self.objects.append(kwargs)


class ConditionalCheckFailedException(Exception):
    pass


class FakeDynamoDB:
    class exceptions:
        ConditionalCheckFailedException = ConditionalCheckFailedException

    def update_item(self, **kwargs):
        return {}


fake_s3 = FakeS3()
fake_dynamodb = FakeDynamoDB()
fake_boto3 = types.SimpleNamespace(
    client=lambda name: fake_s3 if name == "s3" else fake_dynamodb
)
sys.modules["boto3"] = fake_boto3

os.environ.update(
    {
        "BUCKET": "feedback-bucket",
        "PREFIX": "feedback",
        "RATE_LIMIT_TABLE": "feedback-rate-limit",
        "MAX_COMPRESSED_BYTES": "1048576",
        "MAX_UNCOMPRESSED_BYTES": "8388608",
        "RATE_LIMIT_MAX_REQUESTS": "3",
        "RATE_LIMIT_WINDOW_SECONDS": "60",
        "RATE_LIMIT_TTL_SECONDS": "3600",
        "MIN_SECONDS_BETWEEN_POSTS": "10",
        "ALLOWED_ORIGIN": "*",
    }
)

spec = importlib.util.spec_from_file_location("lambda_function", $encodedPath)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

payload = {
    "schemaName": "caverno_feedback_submission",
    "submissionId": "submission-sk-abcdefghijklmnopqrstuvwxyz",
    "feedback": "Bearer plain-secret-token and https://user:pass@example.com/path?token=querysecret",
    "context": {
        "apiKey": "sk-abcdefghijklmnopqrstuvwxyz",
        "nested": {
            "githubToken": "ghp_abcdefghijklmnopqrstuvwxyz123456",
            "safe": "normal text",
        },
    },
    "sessionLog": {
        "path": "/tmp/session.log?api_key=pathsecret",
        "content": "Authorization: Bearer content-secret-token\\nOPENAI_API_KEY=sk-abcdefghijklmnopqrstuvwxyz\\n",
    },
}
body = gzip.compress(json.dumps(payload).encode("utf-8"))
event = {
    "headers": {
        "content-encoding": "gzip",
        "x-caverno-feedback-schema": "caverno_feedback_submission",
    },
    "body": base64.b64encode(body).decode("ascii"),
    "isBase64Encoded": True,
    "requestContext": {"http": {"method": "POST", "sourceIp": "127.0.0.1"}},
}

response = module.handler(event, None)
assert response["statusCode"] == 200, response
assert len(fake_s3.objects) == 1
stored = fake_s3.objects[0]["Body"].decode("utf-8")
key = fake_s3.objects[0]["Key"]
assert "sk-abcdefghijklmnopqrstuvwxyz" not in stored
assert "sk-abcdefghijklmnopqrstuvwxyz" not in key
assert "plain-secret-token" not in stored
assert "content-secret-token" not in stored
assert "ghp_abcdefghijklmnopqrstuvwxyz123456" not in stored
assert "user:pass" not in stored
assert "querysecret" not in stored
assert "pathsecret" not in stored
assert "[REDACTED]" in stored
assert "[REDACTED_OPENAI_API_KEY]" in stored
assert "[REDACTED_GITHUB_TOKEN]" in stored
assert "[REDACTED_AUTHORIZATION]" in stored
assert "[REDACTED_USER]:[REDACTED_PASSWORD]" in stored
assert "normal text" in stored
print("stored key:", key)
''';
}
