import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/core/types/assistant_mode.dart';
import 'package:caverno/features/chat/domain/services/model_edit_apply_telemetry_service.dart';
import 'package:caverno/features/chat/domain/services/weak_model_edit_harness_service.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';

void main() {
  test('injects edit_file guidance for weak coding profiles', () {
    final context = WeakModelEditHarnessService.buildPromptContext(
      assistantMode: AssistantMode.coding,
      toolNames: const ['read_file', 'edit_file'],
      profile: const ModelCapabilityProfile(
        id: 'profile-1',
        baseUrl: 'http://localhost:1234/v1',
        model: 'weak-model',
        toolCallStyle: ModelToolCallStyle.embeddedToolTags,
        structuredOutputSupport: ModelStructuredOutputSupport.none,
        editFormatPreference: ModelEditFormatPreference.searchReplace,
      ),
    );

    expect(context, contains('LL15 WEAK-MODEL EDIT HARNESS'));
    expect(context, contains('edit_file'));
    expect(context, contains('old_text'));
    expect(context, contains('new_text'));
    expect(context, contains('replace_all=false'));
    expect(context, contains('old_text was not found'));
    expect(context, contains('"path":"lib/example.dart"'));
  });

  test('injects for unknown profiles when edit_file is available', () {
    final context = WeakModelEditHarnessService.buildPromptContext(
      assistantMode: AssistantMode.plan,
      toolNames: const ['edit_file'],
      profile: null,
    );

    expect(context, contains('LL15 WEAK-MODEL EDIT HARNESS'));
  });

  test('skips guidance when edit_file is unavailable', () {
    final context = WeakModelEditHarnessService.buildPromptContext(
      assistantMode: AssistantMode.coding,
      toolNames: const ['read_file', 'write_file'],
      profile: const ModelCapabilityProfile(
        id: 'profile-1',
        baseUrl: 'http://localhost:1234/v1',
        model: 'weak-model',
        structuredOutputSupport: ModelStructuredOutputSupport.none,
      ),
    );

    expect(context, isEmpty);
  });

  test('skips guidance outside coding modes', () {
    final context = WeakModelEditHarnessService.buildPromptContext(
      assistantMode: AssistantMode.general,
      toolNames: const ['edit_file'],
      profile: const ModelCapabilityProfile(
        id: 'profile-1',
        baseUrl: 'http://localhost:1234/v1',
        model: 'weak-model',
        structuredOutputSupport: ModelStructuredOutputSupport.none,
      ),
    );

    expect(context, isEmpty);
  });

  test('skips few-shot overhead for strong structured profiles', () {
    final context = WeakModelEditHarnessService.buildPromptContext(
      assistantMode: AssistantMode.coding,
      toolNames: const ['read_file', 'edit_file'],
      profile: const ModelCapabilityProfile(
        id: 'profile-1',
        baseUrl: 'http://localhost:1234/v1',
        model: 'strong-model',
        toolCallStyle: ModelToolCallStyle.nativeToolCalls,
        structuredOutputSupport: ModelStructuredOutputSupport.jsonSchema,
        editFormatPreference: ModelEditFormatPreference.searchReplace,
      ),
    );

    expect(context, isEmpty);
  });

  test('includes observed edit failure rate for weak profiles', () {
    final context = WeakModelEditHarnessService.buildPromptContext(
      assistantMode: AssistantMode.coding,
      toolNames: const ['read_file', 'edit_file'],
      profile: const ModelCapabilityProfile(
        id: 'profile-1',
        baseUrl: 'http://localhost:1234/v1',
        model: 'weak-model',
        toolCallStyle: ModelToolCallStyle.embeddedToolTags,
        structuredOutputSupport: ModelStructuredOutputSupport.none,
        probeMetadata: {
          ModelEditApplyTelemetryService.attemptsKey: '4',
          ModelEditApplyTelemetryService.failureRateKey: '0.500',
        },
      ),
    );

    expect(context, contains('50.0% over 4 attempts'));
  });
}
