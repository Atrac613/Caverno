import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/logger.dart';
import '../domain/entities/app_settings.dart';
import '../domain/services/live_llm_benchmark_artifact_importer.dart';

final liveLlmBenchmarkArtifactFileServiceProvider =
    Provider<LiveLlmBenchmarkArtifactFileService>((ref) {
      return LiveLlmBenchmarkArtifactFileService();
    });

class LiveLlmBenchmarkArtifactFileService {
  Future<ModelCapabilityProfile?> importProfile({
    required Iterable<ModelCapabilityProfile> existingProfiles,
  }) async {
    appLog('[BenchmarkImport] Opening benchmark artifact picker');
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) {
      appLog('[BenchmarkImport] Import cancelled');
      return null;
    }

    final file = result.files.first;
    final content = file.bytes != null
        ? utf8.decode(file.bytes!)
        : file.path != null
        ? await File.fromUri(Uri.file(file.path!)).readAsString()
        : throw const FormatException(
            'Selected benchmark artifact has no readable content',
          );
    final decoded = jsonDecode(content);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Benchmark artifact must be a JSON object');
    }
    return LiveLlmBenchmarkArtifactImporter.importProfile(
      decoded,
      existingProfiles: existingProfiles,
    );
  }
}
