import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/settings/domain/entities/app_settings.dart';

const _handoffSchemaName = 'caverno_personal_eval_profile_handoff';
const _applyResultSchemaName = 'caverno_personal_eval_profile_handoff_apply';

Future<void> main(List<String> args) async {
  final options = PersonalEvalProfileHandoffApplyOptions.parse(args);
  if (options == null) {
    stderr.writeln(
      'Usage: dart run tool/personal_eval_profile_handoff_apply.dart '
      '--handoff PATH --settings PATH '
      '[--dry-run | --apply (--out PATH | --in-place)]',
    );
    exitCode = 64;
    return;
  }

  final PersonalEvalProfileHandoffApplyResult result;
  try {
    result = await applyPersonalEvalProfileHandoff(
      handoffFile: File(options.handoffPath),
      settingsFile: File(options.settingsPath),
      outFile: options.outPath == null ? null : File(options.outPath!),
      inPlace: options.inPlace,
      dryRun: options.dryRun,
    );
  } on FileSystemException catch (error) {
    stderr.writeln(error.message);
    if (error.path != null) {
      stderr.writeln(error.path);
    }
    exitCode = 66;
    return;
  } on PersonalEvalProfileHandoffApplyException catch (error) {
    stderr.writeln(error.message);
    exitCode = 1;
    return;
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    exitCode = 65;
    return;
  } on ArgumentError catch (error) {
    stderr.writeln(error.message);
    exitCode = 64;
    return;
  }

  stdout.writeln(result.toMarkdown());
}

Future<PersonalEvalProfileHandoffApplyResult> applyPersonalEvalProfileHandoff({
  required File handoffFile,
  required File settingsFile,
  File? outFile,
  bool inPlace = false,
  bool dryRun = true,
}) async {
  if (inPlace && outFile != null) {
    throw ArgumentError('Choose either --out or --in-place, not both.');
  }
  if (!dryRun && !inPlace && outFile == null) {
    throw ArgumentError('Applying a handoff requires --out or --in-place.');
  }
  if (!handoffFile.existsSync()) {
    throw FileSystemException(
      'Profile handoff file not found.',
      handoffFile.path,
    );
  }
  if (!settingsFile.existsSync()) {
    throw FileSystemException('Settings file not found.', settingsFile.path);
  }

  final handoff = _ProfileHandoffSnapshot.fromJson(
    await _readJsonObject(handoffFile),
    path: handoffFile.path,
  );
  handoff.ensureReady();

  final inputSettings = AppSettings.fromJson(
    await _readJsonObject(settingsFile),
  );
  final application = _applyHandoffToSettings(inputSettings, handoff);
  final outputFile = inPlace ? settingsFile : outFile;

  if (!dryRun && outputFile != null) {
    await outputFile.parent.create(recursive: true);
    await outputFile.writeAsString(_encodeJson(application.settings.toJson()));
  }

  return PersonalEvalProfileHandoffApplyResult(
    schemaName: _applyResultSchemaName,
    schemaVersion: 1,
    handoffPath: handoffFile.path,
    settingsPath: settingsFile.path,
    outputPath: outputFile?.path,
    dryRun: dryRun,
    wroteSettings: !dryRun && outputFile != null,
    changed: !_sameJson(inputSettings.toJson(), application.settings.toJson()),
    createdProfile: application.createdProfile,
    targetProfileId: handoff.target.profileId,
    metadataPatch: handoff.metadataPatch,
    updatedSettings: application.settings,
    updatedProfile: application.profile,
  );
}

final class PersonalEvalProfileHandoffApplyOptions {
  const PersonalEvalProfileHandoffApplyOptions({
    required this.handoffPath,
    required this.settingsPath,
    required this.dryRun,
    required this.inPlace,
    this.outPath,
  });

  final String handoffPath;
  final String settingsPath;
  final String? outPath;
  final bool dryRun;
  final bool inPlace;

  static PersonalEvalProfileHandoffApplyOptions? parse(List<String> args) {
    String? handoffPath;
    String? settingsPath;
    String? outPath;
    var apply = false;
    var dryRunFlag = false;
    var inPlace = false;

    for (var index = 0; index < args.length; index += 1) {
      final arg = args[index];
      switch (arg) {
        case '--handoff':
          final value = _nextValue(args, ++index);
          if (value == null) return null;
          handoffPath = value;
        case '--settings':
          final value = _nextValue(args, ++index);
          if (value == null) return null;
          settingsPath = value;
        case '--out':
          final value = _nextValue(args, ++index);
          if (value == null) return null;
          outPath = value;
        case '--apply':
          apply = true;
        case '--dry-run':
          dryRunFlag = true;
        case '--in-place':
          inPlace = true;
        default:
          return null;
      }
    }

    if (handoffPath == null || settingsPath == null) {
      return null;
    }
    if (apply && dryRunFlag) {
      return null;
    }
    if (inPlace && outPath != null) {
      return null;
    }
    if (apply && !inPlace && outPath == null) {
      return null;
    }

    return PersonalEvalProfileHandoffApplyOptions(
      handoffPath: handoffPath,
      settingsPath: settingsPath,
      outPath: outPath,
      dryRun: !apply,
      inPlace: inPlace,
    );
  }

  static String? _nextValue(List<String> args, int index) {
    if (index >= args.length) {
      return null;
    }
    final value = args[index];
    return value.startsWith('--') ? null : value;
  }
}

final class PersonalEvalProfileHandoffApplyResult {
  const PersonalEvalProfileHandoffApplyResult({
    required this.schemaName,
    required this.schemaVersion,
    required this.handoffPath,
    required this.settingsPath,
    required this.outputPath,
    required this.dryRun,
    required this.wroteSettings,
    required this.changed,
    required this.createdProfile,
    required this.targetProfileId,
    required this.metadataPatch,
    required this.updatedSettings,
    required this.updatedProfile,
  });

  final String schemaName;
  final int schemaVersion;
  final String handoffPath;
  final String settingsPath;
  final String? outputPath;
  final bool dryRun;
  final bool wroteSettings;
  final bool changed;
  final bool createdProfile;
  final String targetProfileId;
  final Map<String, String> metadataPatch;
  final AppSettings updatedSettings;
  final ModelCapabilityProfile updatedProfile;

  Map<String, dynamic> toJson() {
    return {
      'schemaName': schemaName,
      'schemaVersion': schemaVersion,
      'handoffPath': handoffPath,
      'settingsPath': settingsPath,
      if (outputPath != null) 'outputPath': outputPath,
      'dryRun': dryRun,
      'wroteSettings': wroteSettings,
      'changed': changed,
      'createdProfile': createdProfile,
      'targetProfileId': targetProfileId,
      'metadataPatch': metadataPatch,
      'updatedProfile': updatedProfile.toJson(),
    };
  }

  String toMarkdown() {
    final buffer = StringBuffer()
      ..writeln('# Personal Eval Profile Handoff Apply')
      ..writeln()
      ..writeln('- Mode: `${dryRun ? 'dry_run' : 'apply'}`')
      ..writeln('- Wrote settings: `$wroteSettings`')
      ..writeln('- Changed settings: `$changed`')
      ..writeln('- Created profile: `$createdProfile`')
      ..writeln('- Target profile id: `$targetProfileId`')
      ..writeln('- Handoff: `$handoffPath`')
      ..writeln('- Settings: `$settingsPath`');
    if (outputPath != null) {
      buffer.writeln('- Output: `$outputPath`');
    }
    buffer
      ..writeln()
      ..writeln('## Metadata Patch')
      ..writeln()
      ..writeln('| Key | Value |')
      ..writeln('|-----|-------|');
    for (final entry in metadataPatch.entries) {
      buffer.writeln(
        '| ${_tableCell(entry.key)} | ${_tableCell(entry.value)} |',
      );
    }
    return buffer.toString();
  }
}

final class PersonalEvalProfileHandoffApplyException implements Exception {
  const PersonalEvalProfileHandoffApplyException(this.message);

  final String message;

  @override
  String toString() => message;
}

final class _SettingsApplication {
  const _SettingsApplication({
    required this.settings,
    required this.profile,
    required this.createdProfile,
  });

  final AppSettings settings;
  final ModelCapabilityProfile profile;
  final bool createdProfile;
}

_SettingsApplication _applyHandoffToSettings(
  AppSettings settings,
  _ProfileHandoffSnapshot handoff,
) {
  final provider = handoff.target.providerValue();
  final expectedProfileId = ModelCapabilityProfile.buildId(
    provider: provider,
    baseUrl: handoff.target.baseUrl,
    model: handoff.target.model,
  );
  if (expectedProfileId != handoff.target.profileId) {
    throw FormatException(
      'Handoff target profile id does not match the normalized profile id.',
    );
  }

  final profiles = List<ModelCapabilityProfile>.from(
    settings.modelCapabilityProfiles,
  );
  final index = profiles.indexWhere(
    (profile) => profile.id == expectedProfileId,
  );
  final ModelCapabilityProfile updatedProfile;
  final createdProfile = index == -1;
  if (createdProfile) {
    updatedProfile = ModelCapabilityProfile(
      id: expectedProfileId,
      provider: provider,
      baseUrl: handoff.target.baseUrl,
      model: handoff.target.model,
      probeMetadata: handoff.metadataPatch,
    ).normalizedForPersistence();
    profiles.add(updatedProfile);
  } else {
    final existing = profiles[index].normalizedForPersistence();
    final metadata = <String, String>{
      ...existing.probeMetadata,
      ...handoff.metadataPatch,
    };
    updatedProfile = existing
        .copyWith(probeMetadata: metadata)
        .normalizedForPersistence();
    profiles[index] = updatedProfile;
  }

  return _SettingsApplication(
    settings: settings.copyWith(modelCapabilityProfiles: profiles),
    profile: updatedProfile,
    createdProfile: createdProfile,
  );
}

final class _ProfileHandoffSnapshot {
  const _ProfileHandoffSnapshot({
    required this.result,
    required this.action,
    required this.readyForProfileUpdate,
    required this.blockers,
    required this.target,
    required this.metadataPatch,
  });

  final String result;
  final String action;
  final bool readyForProfileUpdate;
  final List<String> blockers;
  final _ProfileHandoffTargetSnapshot target;
  final Map<String, String> metadataPatch;

  factory _ProfileHandoffSnapshot.fromJson(
    Map<String, dynamic> json, {
    required String path,
  }) {
    final schemaName = _asString(json['schemaName']);
    if (schemaName != _handoffSchemaName) {
      throw FormatException('Invalid personal eval profile handoff in $path.');
    }
    final targetJson = _asStringMap(json['target']);
    if (targetJson == null) {
      throw FormatException('Missing handoff target in $path.');
    }
    return _ProfileHandoffSnapshot(
      result: _requiredString(json, 'result', path),
      action: _requiredString(json, 'action', path),
      readyForProfileUpdate: _requiredBool(json, 'readyForProfileUpdate', path),
      blockers: _stringList(json['blockers']),
      target: _ProfileHandoffTargetSnapshot.fromJson(targetJson, path: path),
      metadataPatch: _stringMap(json['probeMetadataPatch'], path: path),
    );
  }

  void ensureReady() {
    if (!readyForProfileUpdate ||
        result != 'ready' ||
        action != 'apply_profile_metadata') {
      final details = blockers.isEmpty
          ? 'no blockers listed'
          : blockers.join('; ');
      throw PersonalEvalProfileHandoffApplyException(
        'Personal eval profile handoff is not ready for profile update: $details',
      );
    }
    if (metadataPatch.isEmpty) {
      throw const PersonalEvalProfileHandoffApplyException(
        'Personal eval profile handoff has no metadata patch.',
      );
    }
  }
}

final class _ProfileHandoffTargetSnapshot {
  const _ProfileHandoffTargetSnapshot({
    required this.provider,
    required this.baseUrl,
    required this.model,
    required this.profileId,
  });

  final String provider;
  final String baseUrl;
  final String model;
  final String profileId;

  factory _ProfileHandoffTargetSnapshot.fromJson(
    Map<String, dynamic> json, {
    required String path,
  }) {
    return _ProfileHandoffTargetSnapshot(
      provider: _requiredString(json, 'provider', path),
      baseUrl: _requiredString(json, 'baseUrl', path),
      model: _requiredString(json, 'model', path),
      profileId: _requiredString(json, 'profileId', path),
    );
  }

  LlmProvider providerValue() {
    try {
      return LlmProvider.values.byName(provider);
    } on ArgumentError {
      throw FormatException('Unsupported profile provider: $provider.');
    }
  }
}

Future<Map<String, dynamic>> _readJsonObject(File file) async {
  final decoded = jsonDecode(await file.readAsString());
  final object = _asStringMap(decoded);
  if (object == null) {
    throw FormatException('Expected a JSON object in ${file.path}.');
  }
  return object;
}

String _encodeJson(Map<String, dynamic> json) {
  return '${const JsonEncoder.withIndent('  ').convert(json)}\n';
}

bool _sameJson(Map<String, dynamic> left, Map<String, dynamic> right) {
  return jsonEncode(left) == jsonEncode(right);
}

String _tableCell(String value) {
  return value.replaceAll('|', r'\|').replaceAll('\n', '<br>');
}

Map<String, dynamic>? _asStringMap(Object? value) {
  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }
  return null;
}

String? _asString(Object? value) => value is String ? value : null;

String _requiredString(Map<String, dynamic> json, String key, String path) {
  final value = _trimToNull(_asString(json[key]));
  if (value == null) {
    throw FormatException('Missing `$key` in $path.');
  }
  return value;
}

bool _requiredBool(Map<String, dynamic> json, String key, String path) {
  final value = json[key];
  if (value is bool) {
    return value;
  }
  throw FormatException('Missing boolean `$key` in $path.');
}

String? _trimToNull(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

List<Object?> _asList(Object? value) {
  if (value is List) {
    return value;
  }
  return const [];
}

List<String> _stringList(Object? value) {
  return _asList(value)
      .map(_asString)
      .nonNulls
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}

Map<String, String> _stringMap(Object? value, {required String path}) {
  final map = _asStringMap(value);
  if (map == null) {
    throw FormatException('Missing metadata patch in $path.');
  }
  final normalized = <String, String>{};
  for (final entry in map.entries) {
    final key = _trimToNull(entry.key);
    final value = _trimToNull(_asString(entry.value));
    if (key == null || value == null) {
      throw FormatException('Invalid metadata patch entry in $path.');
    }
    normalized[key] = value;
  }
  return normalized;
}
