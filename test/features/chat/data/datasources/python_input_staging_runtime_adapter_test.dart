import 'dart:io';

import 'package:caverno/features/chat/data/datasources/python_script_tool_runtime_adapter.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/services/python_script_tool_contract.dart';
import 'package:test/test.dart';

import 'python_script_runtime_test_support.dart';

void main() {
  PythonRuntimeStagingRequest request({Message? message}) {
    final input = PythonScriptRuntimeInput(
      owner: testPythonOwner,
      toolCall: testPythonToolCall(),
    );
    final messages = message == null ? const <Message>[] : [message];
    final identity = PythonScriptRuntimeIdentity(
      invocation: input.identity,
      ownerMessages: messages,
    );
    return PythonRuntimeStagingRequest(
      identity: identity,
      attempt: PythonStagingAttempt(
        owner: identity.owner,
        toolCallId: identity.toolCallId,
        toolName: identity.toolName,
      ),
      attachment: message == null
          ? null
          : PythonInputAttachment.fromMessage(message),
    );
  }

  PythonRuntimeCleanupRequest cleanupRequest(
    PythonRuntimeStagingRequest staging,
    PythonStagingDirectoryIdentity directory,
  ) {
    return PythonRuntimeCleanupRequest(
      identity: PythonStagingCleanupIdentity(
        runtime: staging.identity,
        attempt: staging.attempt,
        directoryIdentity: directory,
      ),
    );
  }

  test('stages and deletes one exact marker-owned directory', () async {
    final adapter = PythonInputStagingRuntimeAdapter(
      nonceFactory: () => 'exact-test-marker',
    );
    final staging = request();

    final staged = await adapter.stage(staging);
    final allocation = staged.value!;
    final directory = Directory(allocation.stagedInputs.workingDirectory);
    final marker = File(
      '${directory.path}${Platform.pathSeparator}'
      '${PythonInputStagingRuntimeAdapter.markerFileName}',
    );

    expect(
      staged.disposition,
      PythonRuntimeAcknowledgementDisposition.completed,
    );
    expect(await directory.exists(), isTrue);
    expect(await marker.readAsString(), 'exact-test-marker');
    expect(allocation.stagedInputs.inputs, isEmpty);

    final cleaned = await adapter.cleanup(
      cleanupRequest(staging, allocation.directoryIdentity),
    );

    expect(cleaned.value, PythonStagingCleanupOutcome.deleted);
    expect(await directory.exists(), isFalse);
  });

  test(
    'copies an owner attachment into the canonical staged directory',
    () async {
      final sourceDirectory = await Directory.systemTemp.createTemp(
        'python_runtime_source_',
      );
      final source = File(
        '${sourceDirectory.path}${Platform.pathSeparator}owner.png',
      );
      await source.writeAsBytes([1, 2, 3, 4]);
      final message = testPythonMessage(originalImagePath: source.path);
      final adapter = PythonInputStagingRuntimeAdapter(
        nonceFactory: () => 'attachment-marker',
      );
      final staging = request(message: message);

      final staged = await adapter.stage(staging);
      final allocation = staged.value!;
      final input = allocation.stagedInputs.inputs.single;

      expect(input['name'], 'attachment_0.png');
      expect(await File(input['path'] as String).readAsBytes(), [1, 2, 3, 4]);
      expect(
        (input['path'] as String).startsWith(
          '${allocation.stagedInputs.workingDirectory}'
          '${Platform.pathSeparator}',
        ),
        isTrue,
      );

      await adapter.cleanup(
        cleanupRequest(staging, allocation.directoryIdentity),
      );
      await sourceDirectory.delete(recursive: true);
    },
  );

  test('refuses cleanup after marker identity is replaced', () async {
    final adapter = PythonInputStagingRuntimeAdapter(
      nonceFactory: () => 'original-marker',
    );
    final staging = request();
    final staged = await adapter.stage(staging);
    final allocation = staged.value!;
    final directory = Directory(allocation.stagedInputs.workingDirectory);
    final marker = File(
      '${directory.path}${Platform.pathSeparator}'
      '${PythonInputStagingRuntimeAdapter.markerFileName}',
    );
    await marker.writeAsString('replacement-marker', flush: true);

    final refused = await adapter.cleanup(
      cleanupRequest(staging, allocation.directoryIdentity),
    );

    expect(refused.value, PythonStagingCleanupOutcome.identityMismatch);
    expect(await directory.exists(), isTrue);

    await marker.writeAsString('original-marker', flush: true);
    final cleaned = await adapter.cleanup(
      cleanupRequest(staging, allocation.directoryIdentity),
    );
    expect(cleaned.value, PythonStagingCleanupOutcome.deleted);
  });
}
