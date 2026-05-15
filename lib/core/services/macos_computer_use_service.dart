import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../utils/logger.dart';
import 'macos_computer_use_setup.dart';
import 'macos_computer_use_tool_policy.dart';
import 'macos_computer_use_transport.dart';

final macosComputerUseServiceProvider = Provider<MacosComputerUseService>((
  ref,
) {
  return MacosComputerUseService();
});

class MacosComputerUseService {
  MacosComputerUseService({
    MacosComputerUsePermissionTransport? permissionTransport,
  }) : _permissionTransport =
           permissionTransport ?? const HelperMacosComputerUseTransport();

  static const MethodChannel _channel = MethodChannel(
    'com.caverno/macos_computer_use',
  );
  static const liveSmokeReportPath = String.fromEnvironment(
    'CAVERNO_MACOS_COMPUTER_USE_SMOKE_REPORT_PATH',
    defaultValue: '/tmp/caverno-macos-computer-use-smoke.json',
  );
  static const existingHelperProbeReportPath = String.fromEnvironment(
    'CAVERNO_MACOS_COMPUTER_USE_EXISTING_HELPER_REPORT_PATH',
    defaultValue: '/tmp/caverno-macos-computer-use-existing-helper-probe.json',
  );

  final MacosComputerUsePermissionTransport _permissionTransport;

  bool get isAvailable => Platform.isMacOS;

  MacosComputerUseBackendInfo get permissionBackendInfo =>
      _permissionTransport.backendInfo;

  Future<String> getHelperStatus() async {
    return _invokeTransportJson(_permissionTransport.helperStatus);
  }

  Future<String> launchHelper() async {
    return _invokeTransportJson(_permissionTransport.launchHelper);
  }

  Future<String> restartHelper() async {
    return _invokeTransportJson(_permissionTransport.restartHelper);
  }

  Future<String> terminateHelperForXpcLaunchAgent() async {
    return _invokeTransportJson(
      _permissionTransport.terminateHelperForXpcLaunchAgent,
    );
  }

  Future<String> registerXpcLaunchAgent() async {
    return _invokeTransportJson(_permissionTransport.registerXpcLaunchAgent);
  }

  Future<String> unregisterXpcLaunchAgent() async {
    return _invokeTransportJson(_permissionTransport.unregisterXpcLaunchAgent);
  }

  Future<String> pingHelper() async {
    return _invokeTransportJson(_permissionTransport.ping);
  }

  Future<String> waitForHelperIpcReady({
    int attempts = 2,
    Duration delay = const Duration(milliseconds: 400),
  }) async {
    final safeAttempts = attempts < 1 ? 1 : attempts;
    final startedAt = DateTime.now();
    final results = <Object>[];

    for (var index = 0; index < safeAttempts; index += 1) {
      final raw = await pingHelper();
      final decoded = _decodeMap(raw);
      results.add(decoded ?? raw);
      if (decoded != null &&
          decoded['ok'] != false &&
          decoded['helperReachable'] != false) {
        return jsonEncode({
          ...decoded,
          'ok': true,
          'helperReachable': true,
          'ipcReady': true,
          'attempts': index + 1,
          'waitedMs': DateTime.now().difference(startedAt).inMilliseconds,
        });
      }
      if (index < safeAttempts - 1) {
        await Future<void>.delayed(delay);
      }
    }

    Map<String, dynamic>? last;
    for (final result in results) {
      if (result is Map) {
        last = Map<String, dynamic>.from(result);
      }
    }
    final failed = <String, dynamic>{
      if (last != null) ...last,
      'ok': false,
      'helperReachable': false,
      'ipcReady': false,
      'code': last?['code'] ?? 'helper_unreachable',
      'error':
          last?['error'] ?? 'Caverno Computer Use IPC did not become ready.',
      'attempts': safeAttempts,
      'waitedMs': DateTime.now().difference(startedAt).inMilliseconds,
      'results': results,
    };
    return jsonEncode(_withNextAction(failed));
  }

  Future<String> getPermissions() async {
    return _invokeTransportJson(_permissionTransport.getPermissions);
  }

  Future<Map<String, dynamic>> _prepareHelperUi() async {
    final helper =
        _decodeMap(
          await _invokeTransportJson(_permissionTransport.launchHelper),
        ) ??
        const <String, dynamic>{};
    final ready =
        _decodeMap(
          await waitForHelperIpcReady(
            attempts: 4,
            delay: const Duration(milliseconds: 250),
          ),
        ) ??
        const <String, dynamic>{};
    return {'helper': helper, 'ipcReady': ready};
  }

  Future<Map<String, dynamic>> _showPermissionOverlayMap({
    required String permission,
    required bool prepareHelperUi,
  }) async {
    final helperUi =
        prepareHelperUi && _permissionTransport.backendInfo.usesSeparateHelper
        ? await _prepareHelperUi()
        : null;
    final overlay =
        _decodeMap(
          await _invokeTransportJson(
            () => _permissionTransport.showPermissionOverlay(
              permission: permission,
            ),
          ),
        ) ??
        const <String, dynamic>{};
    final response = <String, dynamic>{...overlay};
    if (helperUi != null) {
      response['helperUi'] = helperUi;
    }
    return response;
  }

  Future<Map<String, dynamic>> _startOnboardingPermissionFlowMap({
    required String permission,
    required bool prepareHelperUi,
  }) async {
    final helperUi =
        prepareHelperUi && _permissionTransport.backendInfo.usesSeparateHelper
        ? await _prepareHelperUi()
        : null;
    final flow =
        _decodeMap(
          await _invokeTransportJson(
            () => _permissionTransport.startOnboardingPermissionFlow(
              permission: permission,
            ),
          ),
        ) ??
        const <String, dynamic>{};
    final response = <String, dynamic>{...flow};
    if (helperUi != null) {
      response['helperUi'] = helperUi;
    }
    return response;
  }

  Future<String> requestPermissions({
    bool accessibility = true,
    bool screenCapture = true,
  }) async {
    if (_permissionTransport.backendInfo.usesSeparateHelper) {
      final responses = <String, dynamic>{};
      final helperUi = await _prepareHelperUi();
      responses['helper'] = helperUi['helper'];
      responses['helperReady'] = helperUi['ipcReady'];
      if (accessibility) {
        responses['accessibility'] = await _showPermissionOverlayMap(
          permission: 'accessibility',
          prepareHelperUi: false,
        );
      }
      if (screenCapture) {
        responses['screenCapture'] = await _showPermissionOverlayMap(
          permission: 'screenRecording',
          prepareHelperUi: false,
        );
      }
      responses['current'] =
          _decodeMap(
            await _invokeTransportJson(_permissionTransport.getPermissions),
          ) ??
          const <String, dynamic>{};
      return jsonEncode(responses);
    }

    final responses = <String, dynamic>{};
    if (accessibility) {
      responses['accessibility'] = await _invokeMap('requestAccessibility');
    }
    if (screenCapture) {
      responses['screenCapture'] = await _invokeMap('requestScreenCapture');
    }
    responses['current'] =
        _decodeMap(
          await _invokeTransportJson(_permissionTransport.getPermissions),
        ) ??
        const <String, dynamic>{};
    return jsonEncode(responses);
  }

  Future<String> openSystemSettings({required String section}) async {
    return _invokeTransportJson(
      () => _permissionTransport.openSystemSettings(section: section),
    );
  }

  Future<String> showPermissionOverlay({required String permission}) async {
    if (_permissionTransport.backendInfo.usesSeparateHelper) {
      return jsonEncode(
        await _showPermissionOverlayMap(
          permission: permission,
          prepareHelperUi: true,
        ),
      );
    }
    return _invokeTransportJson(
      () => _permissionTransport.showPermissionOverlay(permission: permission),
    );
  }

  Future<String> startOnboardingPermissionFlow({
    required String permission,
  }) async {
    if (_permissionTransport.backendInfo.usesSeparateHelper) {
      return jsonEncode(
        await _startOnboardingPermissionFlowMap(
          permission: permission,
          prepareHelperUi: true,
        ),
      );
    }
    return _invokeTransportJson(
      () => _permissionTransport.startOnboardingPermissionFlow(
        permission: permission,
      ),
    );
  }

  Future<String> stopHelperWork() async {
    return _invokeTransportJson(_permissionTransport.stopAll);
  }

  Future<String> getLastLiveSmokeReport() async {
    return _readJsonReport(
      path: liveSmokeReportPath,
      unsupportedError:
          'macOS computer use live smoke reports are only available on macOS.',
      missingCode: 'live_smoke_report_missing',
      missingError:
          'No macOS computer use live smoke report has been written yet.',
      invalidCode: 'live_smoke_report_invalid',
      invalidError:
          'The macOS computer use live smoke report is not a JSON object.',
      readFailedCode: 'live_smoke_report_read_failed',
    );
  }

  Future<String> getLastExistingHelperProbeReport() async {
    return _readJsonReport(
      path: existingHelperProbeReportPath,
      unsupportedError:
          'macOS computer use existing-helper probe reports are only available on macOS.',
      missingCode: 'existing_helper_probe_report_missing',
      missingError:
          'No macOS computer use existing-helper probe report has been written yet.',
      invalidCode: 'existing_helper_probe_report_invalid',
      invalidError:
          'The macOS computer use existing-helper probe report is not a JSON object.',
      readFailedCode: 'existing_helper_probe_report_read_failed',
    );
  }

  Future<String> _readJsonReport({
    required String path,
    required String unsupportedError,
    required String missingCode,
    required String missingError,
    required String invalidCode,
    required String invalidError,
    required String readFailedCode,
  }) async {
    if (!Platform.isMacOS) {
      return jsonEncode({
        'ok': false,
        'code': 'unsupported_platform',
        'error': unsupportedError,
        'path': path,
      });
    }

    final file = File(path);
    try {
      if (!await file.exists()) {
        return jsonEncode({
          'ok': false,
          'code': missingCode,
          'error': missingError,
          'path': path,
        });
      }

      final raw = await file.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return jsonEncode({
          'ok': true,
          'path': path,
          'report': Map<String, dynamic>.from(decoded),
        });
      }
      return jsonEncode({
        'ok': false,
        'code': invalidCode,
        'error': invalidError,
        'path': path,
      });
    } catch (error) {
      return jsonEncode({
        'ok': false,
        'code': readFailedCode,
        'error': error.toString(),
        'path': path,
      });
    }
  }

  Future<String> screenshot(Map<String, dynamic> arguments) async {
    return _invokeJson('screenshot', _normalizeCoordinateArguments(arguments));
  }

  Future<String> listDisplays(Map<String, dynamic> arguments) async {
    return _invokeJson(
      'listDisplays',
      _normalizeCoordinateArguments(arguments),
    );
  }

  Future<String> listWindows(Map<String, dynamic> arguments) async {
    return _invokeJson('listWindows', arguments);
  }

  Future<String> accessibilitySnapshot(Map<String, dynamic> arguments) async {
    return _invokeJson('accessibilitySnapshot', arguments);
  }

  Future<String> focusWindow(Map<String, dynamic> arguments) async {
    return _invokeJson(
      'focusWindow',
      _normalizeElementTargetArguments(arguments),
    );
  }

  Future<String> screenshotWindow(Map<String, dynamic> arguments) async {
    return _invokeJson('screenshotWindow', arguments);
  }

  Future<String> click(Map<String, dynamic> arguments) async {
    return _invokeJson(
      'click',
      _normalizeCoordinateArguments(
        _normalizeElementTargetArguments(arguments),
      ),
    );
  }

  Future<String> moveMouse(Map<String, dynamic> arguments) async {
    return _invokeJson('moveMouse', _normalizeCoordinateArguments(arguments));
  }

  Future<String> drag(Map<String, dynamic> arguments) async {
    return _invokeJson('drag', _normalizeCoordinateArguments(arguments));
  }

  Future<String> scroll(Map<String, dynamic> arguments) async {
    return _invokeJson('scroll', _normalizeCoordinateArguments(arguments));
  }

  Future<String> typeText(Map<String, dynamic> arguments) async {
    return _invokeJson('typeText', _normalizeElementTargetArguments(arguments));
  }

  Future<String> pressKey(Map<String, dynamic> arguments) async {
    final normalized = Map<String, dynamic>.from(arguments);
    final modifiers = normalized['modifiers'];
    if (modifiers is List) {
      normalized['modifiers'] = modifiers.map((value) => '$value').toList();
    }
    return _invokeJson('pressKey', normalized);
  }

  Future<String> startSystemAudioRecording(
    Map<String, dynamic> arguments,
  ) async {
    return _invokeJson('startSystemAudioRecording', arguments);
  }

  Future<String> stopSystemAudioRecording() async {
    return _invokeJson('stopSystemAudioRecording');
  }

  Future<String> visionObserve(Map<String, dynamic> arguments) async {
    final target = _stringValue(arguments['target']).isNotEmpty
        ? _stringValue(arguments['target'])
        : arguments['window_id'] != null || arguments['windowId'] != null
        ? 'window'
        : 'display';
    final includeWindows =
        arguments['include_windows'] != false &&
        arguments['includeWindows'] != false;
    final maxWidth = _intValue(
      arguments['max_width'] ?? arguments['maxWidth'],
    )?.clamp(200, 1600);
    final requestedWindowId = _intValue(
      arguments['window_id'] ?? arguments['windowId'],
    );
    final requestedDisplayId = _intValue(
      arguments['display_id'] ?? arguments['displayId'],
    );
    final includeDisplays =
        arguments['include_displays'] != false &&
        arguments['includeDisplays'] != false;
    final spaceScope = _windowSpaceScope(arguments);

    final permissions = _decodeMap(await getPermissions());
    Map<String, dynamic>? displaysResult;
    if (includeDisplays || target == 'display') {
      displaysResult = _decodeMap(await listDisplays(const {}));
    }
    Map<String, dynamic>? windowsResult;
    if (includeWindows || target == 'front_window') {
      windowsResult = _decodeMap(
        await listWindows({
          'include_current_app': false,
          'max_windows': _intValue(arguments['max_windows']) ?? 20,
          'space_scope': spaceScope,
        }),
      );
    }

    final resolvedWindowId = target == 'front_window'
        ? _firstWindowId(windowsResult)
        : requestedWindowId;
    final captureArguments = <String, dynamic>{};
    if (maxWidth != null) {
      captureArguments['max_width'] = maxWidth;
    }
    if (requestedDisplayId != null) {
      captureArguments['display_id'] = requestedDisplayId;
    }

    final captureTarget = switch (target) {
      'window' || 'front_window' when resolvedWindowId != null => 'window',
      _ => 'display',
    };
    if (captureTarget == 'window') {
      captureArguments['window_id'] = resolvedWindowId;
    }

    final captureRaw = captureTarget == 'window'
        ? await screenshotWindow(captureArguments)
        : await screenshot(captureArguments);
    final capture =
        _decodeMap(captureRaw) ??
        {
          'ok': false,
          'code': 'invalid_capture_response',
          'error':
              'Computer vision observation did not receive JSON capture data.',
          'raw': captureRaw,
        };
    final captureOk = capture['ok'] != false;
    final imageBase64 = capture['imageBase64'];
    final imageMimeType = capture['imageMimeType'] as String? ?? 'image/png';
    final captureMetadata = Map<String, dynamic>.from(capture)
      ..remove('imageBase64');
    final elementGrounding = await _visionElementGrounding(
      arguments: arguments,
      captureTarget: captureTarget,
      resolvedWindowId: resolvedWindowId,
      captureOk: captureOk,
    );

    final targetSummary = <String, dynamic>{
      'requested': target,
      'resolved': captureTarget,
      'spaceScope': spaceScope,
    };
    if (resolvedWindowId != null) {
      targetSummary['windowId'] = resolvedWindowId;
    }
    if (requestedDisplayId != null) {
      targetSummary['displayId'] = requestedDisplayId;
    } else if (capture['displayId'] != null) {
      targetSummary['displayId'] = capture['displayId'];
    }

    final result = <String, dynamic>{
      'ok': captureOk && imageBase64 is String && imageBase64.isNotEmpty,
      'schemaName': 'macos_computer_use_vision_observation',
      'schemaVersion': 1,
      'observationId': 'vision-${DateTime.now().microsecondsSinceEpoch}',
      'target': targetSummary,
      'coordinateSpace': capture['coordinateSpace'] ?? 'screenshot_pixels',
      'coordinateGuidance': {
        'useLatestObservation': true,
        'includeSourceSize': true,
        'sourceWidth': capture['width'],
        'sourceHeight': capture['height'],
        'windowId': capture['windowId'] ?? resolvedWindowId,
        'displayId': capture['displayId'] ?? requestedDisplayId,
      },
      'permissions': permissions ?? const <String, dynamic>{},
      if (displaysResult != null)
        'displays': _redactedDisplaysResult(displaysResult),
      if (windowsResult != null)
        'windows': _redactedWindowsResult(windowsResult),
      'elementGrounding': elementGrounding,
      'observation': captureMetadata,
      if (imageBase64 is String && imageBase64.isNotEmpty)
        'imageBase64': imageBase64,
      'imageMimeType': imageMimeType,
      'allowedNextTools': _visionAllowedNextTools,
      'approvalRequiredTools': _visionApprovalRequiredTools,
      'armingRequiredTools': _visionArmingRequiredTools,
      'actionProposalPolicy': _visionActionProposalPolicy(),
      'productionActionPolicy':
          MacosComputerUseToolPolicy.productionActionPolicy().toJson(),
      'nextAction': _visionNextAction(
        captureOk: captureOk,
        imageAttached: imageBase64 is String && imageBase64.isNotEmpty,
        capture: capture,
        displayCount: _intValue(displaysResult?['count']),
        target: target,
        spaceScope: spaceScope,
        windowsResult: windowsResult,
      ),
    };

    if (result['ok'] != true) {
      result['code'] = capture['code'] ?? 'vision_observation_failed';
      result['error'] =
          capture['error'] ?? 'Computer vision observation failed.';
    }
    return jsonEncode(result);
  }

  Future<Map<String, dynamic>> _visionElementGrounding({
    required Map<String, dynamic> arguments,
    required String captureTarget,
    required int? resolvedWindowId,
    required bool captureOk,
  }) async {
    final includeAccessibility =
        arguments['include_accessibility'] != false &&
        arguments['includeAccessibility'] != false;
    final maxCandidates = _intValue(
      arguments['max_candidate_elements'] ?? arguments['maxCandidateElements'],
    )?.clamp(1, 30);

    Map<String, dynamic> base({
      required String status,
      String? code,
      String? error,
      Map<String, dynamic>? extra,
    }) {
      final response = <String, dynamic>{
        'schemaName': 'macos_computer_use_element_grounding',
        'schemaVersion': 1,
        'sourceTool': 'computer_accessibility_snapshot',
        'status': status,
        'candidateElements': const <Map<String, dynamic>>[],
        'candidateElementCount': 0,
        'coordinateSpace': 'screen_points',
        'windowId': resolvedWindowId,
        'redaction': const {
          'policy': 'metadata_only',
          'valuesOmitted': true,
          'selectedTextOmitted': true,
          'rawAttributeValuesOmitted': true,
        },
        if (extra != null) ...extra,
      };
      if (code != null) {
        response['code'] = code;
      }
      if (error != null) {
        response['error'] = error;
      }
      return response;
    }

    if (!includeAccessibility) {
      return base(status: 'skipped', code: 'accessibility_grounding_disabled');
    }
    if (!captureOk) {
      return base(status: 'skipped', code: 'capture_not_ready');
    }
    if (captureTarget != 'window' || resolvedWindowId == null) {
      return base(status: 'skipped', code: 'window_target_required');
    }

    final snapshotArguments = <String, dynamic>{
      'target': 'window',
      'window_id': resolvedWindowId,
      'max_elements':
          _intValue(
            arguments['max_accessibility_elements'] ??
                arguments['maxAccessibilityElements'],
          ) ??
          50,
      'max_depth':
          _intValue(
            arguments['max_accessibility_depth'] ??
                arguments['maxAccessibilityDepth'],
          ) ??
          4,
      'label_max_characters':
          _intValue(
            arguments['label_max_characters'] ??
                arguments['labelMaxCharacters'],
          ) ??
          120,
    };
    if (maxCandidates != null) {
      snapshotArguments['max_candidate_elements'] = maxCandidates;
    }

    final rawSnapshot = await accessibilitySnapshot(snapshotArguments);
    final snapshot = _decodeMap(rawSnapshot);
    if (snapshot == null) {
      return base(
        status: 'failed',
        code: 'invalid_accessibility_snapshot_response',
        error:
            'Computer vision observation did not receive JSON accessibility snapshot data.',
        extra: {'raw': rawSnapshot},
      );
    }
    if (snapshot['ok'] == false) {
      return base(
        status: _groundingBlockedStatus(snapshot['code']),
        code: snapshot['code'] as String? ?? 'accessibility_snapshot_failed',
        error:
            snapshot['error'] as String? ??
            'Accessibility snapshot was not available.',
        extra: {'snapshot': _redactedAccessibilitySnapshotMetadata(snapshot)},
      );
    }

    final candidates = _candidateElementsFromSnapshot(
      snapshot,
      maxCandidates: maxCandidates ?? 12,
    );
    return {
      'schemaName': 'macos_computer_use_element_grounding',
      'schemaVersion': 1,
      'sourceTool': 'computer_accessibility_snapshot',
      'status': 'ready',
      'observationId': snapshot['observationId'] ?? snapshot['snapshotId'],
      'snapshotId': snapshot['snapshotId'] ?? snapshot['observationId'],
      'windowId': resolvedWindowId,
      'coordinateSpace': snapshot['coordinateSpace'] ?? 'screen_points',
      'inputOrigin': snapshot['inputOrigin'] ?? 'top_left',
      'bounds': snapshot['bounds'] ?? const <String, dynamic>{},
      'elementCount': snapshot['elementCount'] ?? candidates.length,
      'candidateElements': candidates,
      'candidateElementCount': candidates.length,
      'redaction': snapshot['redaction'] ?? const <String, dynamic>{},
      'snapshotTruncated': snapshot['truncated'] == true,
      'truncation': snapshot['truncation'] ?? const <String, dynamic>{},
      'candidateSelection': {
        'maxCandidates': maxCandidates ?? 12,
        'preferredRoles': _groundingPreferredRoleTokens,
        'fallbackUsed': candidates.isNotEmpty && !_hasPreferredRole(candidates),
      },
      'nextAction':
          'When proposing an approved desktop action, cite a candidate elementId in target.elementId when it matches the visible screenshot target.',
    };
  }

  Map<String, dynamic> _visionActionProposalPolicy() {
    final toolPolicies = _visionAllowedNextTools
        .map((toolName) {
          final decision = MacosComputerUseToolPolicy.actionProposalDecision(
            toolName: toolName,
          );
          if (decision == null) {
            return null;
          }
          return {
            'toolName': toolName,
            'requiresUserApproval': decision.requiresUserApproval,
            'requiresTargetApproval': decision.requiresTargetApproval,
            'requiresExactTextApproval': decision.requiresExactTextApproval,
            'requiresSeparatePublicActionApproval':
                decision.requiresSeparatePublicActionApproval,
            'allowedAsObserveOnlyProposal':
                decision.allowedAsObserveOnlyProposal,
            'boundaries': decision.boundaries
                .map((boundary) => boundary.name)
                .toList(growable: false),
            'blockerCodes': decision.blockerCodes,
            'targetSafety': decision.targetSafety.toJson(),
            'nextAction': decision.nextAction,
          };
        })
        .nonNulls
        .toList(growable: false);

    return {
      'schemaName': 'macos_computer_use_action_proposal_policy',
      'schemaVersion': 1,
      'productionActionPolicy':
          MacosComputerUseToolPolicy.productionActionPolicy().toJson(),
      'targetMetadataKey': 'target',
      'rules': [
        'Observation tools can remain in planning without approval.',
        'Pointer, keyboard, and focus actions must include a concrete target before user approval.',
        'computer_type_text must include the exact text that will be typed.',
        'Posting, sending, submitting, or publishing controls must set target.risk=public_action and require separate public action approval.',
        'Secure fields, credential prompts, payment flows, and destructive controls must set target.risk to secure_field, credential, payment, or destructive and are blocked until manually handled.',
        'System audio recording requires separate recording approval.',
      ],
      'targetSchema': {
        'label': 'Visible label or accessible name.',
        'role': 'Visible or accessibility role.',
        'elementId':
            'Optional elementId from elementGrounding.candidateElements in the latest computer_vision_observe result.',
        'action': 'Intended action, such as click, submit, or publish.',
        'risk':
            'Use public_action, secure_field, credential, payment, destructive, input, sensitive, or unknown.',
      },
      'toolPolicies': toolPolicies,
    };
  }

  Map<String, dynamic> _normalizeCoordinateArguments(
    Map<String, dynamic> arguments,
  ) {
    final normalized = Map<String, dynamic>.from(arguments);
    for (final key in const [
      'x',
      'y',
      'from_x',
      'from_y',
      'to_x',
      'to_y',
      'source_width',
      'source_height',
    ]) {
      final value = normalized[key];
      if (value is num) {
        normalized[key] = value.toDouble();
      }
    }
    for (final key in const [
      'window_id',
      'windowId',
      'display_id',
      'displayId',
      'display_index',
      'displayIndex',
    ]) {
      final value = normalized[key];
      if (value is num) {
        normalized[key] = value.toInt();
      }
    }
    return normalized;
  }

  Map<String, dynamic> _normalizeElementTargetArguments(
    Map<String, dynamic> arguments,
  ) {
    final normalized = Map<String, dynamic>.from(arguments);
    if (normalized['element_id'] == null && normalized['elementId'] == null) {
      final target = normalized['target'];
      if (target is Map) {
        final targetElementId = target['element_id'] ?? target['elementId'];
        if (targetElementId != null) {
          normalized['element_id'] = '$targetElementId';
        }
      }
    }
    return normalized;
  }

  String _stringValue(Object? value) {
    return value is String ? value.trim() : '';
  }

  int? _intValue(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  int? _firstWindowId(Map<String, dynamic>? windowsResult) {
    final windows = windowsResult?['windows'];
    if (windows is! List) return null;
    for (final window in windows) {
      if (window is! Map) continue;
      final id = _intValue(window['windowId'] ?? window['window_id']);
      if (id != null) return id;
    }
    return null;
  }

  String _windowSpaceScope(Map<String, dynamic> arguments) {
    final raw = _stringValue(
      arguments['space_scope'] ?? arguments['spaceScope'],
    ).toLowerCase();
    return switch (raw) {
      'all' ||
      'all_spaces' ||
      'all_desktops' ||
      'all_desktop_spaces' => 'all_spaces',
      _ => 'active_space',
    };
  }

  bool _windowResultHasInactiveSpaceWindows(Map<String, dynamic>? result) {
    final windows = result?['windows'];
    if (windows is! List) return false;
    return windows.whereType<Map>().any((window) {
      final status = _stringValue(window['spaceStatus']).toLowerCase();
      return status.isNotEmpty && status != 'active_space_visible';
    });
  }

  Map<String, dynamic> _redactedWindowsResult(Map<String, dynamic> result) {
    final redacted = Map<String, dynamic>.from(result);
    final windows = redacted['windows'];
    if (windows is List) {
      redacted['windows'] = windows
          .whereType<Map>()
          .map((window) => Map<String, dynamic>.from(window))
          .toList(growable: false);
    }
    return redacted;
  }

  Map<String, dynamic> _redactedDisplaysResult(Map<String, dynamic> result) {
    final redacted = Map<String, dynamic>.from(result);
    final displays = redacted['displays'];
    if (displays is List) {
      redacted['displays'] = displays
          .whereType<Map>()
          .map((display) => Map<String, dynamic>.from(display))
          .toList(growable: false);
    }
    return redacted;
  }

  String _groundingBlockedStatus(Object? code) {
    return switch (code) {
      'accessibility_denied' || 'accessibility_window_not_found' => 'blocked',
      _ => 'failed',
    };
  }

  Map<String, dynamic> _redactedAccessibilitySnapshotMetadata(
    Map<String, dynamic> snapshot,
  ) {
    final metadata = Map<String, dynamic>.from(snapshot)
      ..remove('elements')
      ..remove('imageBase64');
    return metadata;
  }

  List<Map<String, dynamic>> _candidateElementsFromSnapshot(
    Map<String, dynamic> snapshot, {
    required int maxCandidates,
  }) {
    final elements = snapshot['elements'];
    if (elements is! List) {
      return const <Map<String, dynamic>>[];
    }
    final normalized = elements
        .whereType<Map>()
        .map((element) => _normalizedGroundingCandidate(element))
        .nonNulls
        .toList(growable: false);
    final preferred = normalized
        .where(_isPreferredGroundingCandidate)
        .take(maxCandidates)
        .toList(growable: false);
    if (preferred.isNotEmpty) {
      return preferred;
    }
    return normalized.take(maxCandidates).toList(growable: false);
  }

  Map<String, dynamic>? _normalizedGroundingCandidate(
    Map<dynamic, dynamic> raw,
  ) {
    final elementId = _stringValue(raw['elementId']);
    final role = _stringValue(raw['role']);
    if (elementId.isEmpty || role.isEmpty) {
      return null;
    }
    final candidate = <String, dynamic>{
      'elementId': elementId,
      'role': role,
      'label': _stringValue(raw['label']),
      'frame': raw['frame'],
      'frameKnown': raw['frameKnown'] == true,
      'enabled': raw['enabled'] == true,
      'enabledKnown': raw['enabledKnown'] == true,
      'focused': raw['focused'] == true,
      'focusedKnown': raw['focusedKnown'] == true,
      'childCount': _intValue(raw['childCount']) ?? 0,
      'redaction': raw['redaction'] ?? const <String, dynamic>{},
    };
    final subrole = _stringValue(raw['subrole']);
    final labelSource = _stringValue(raw['labelSource']);
    if (subrole.isNotEmpty) {
      candidate['subrole'] = subrole;
    }
    if (labelSource.isNotEmpty) {
      candidate['labelSource'] = labelSource;
    }
    final parentId = _stringValue(raw['parentId']);
    if (parentId.isNotEmpty) {
      candidate['parentId'] = parentId;
    }
    return candidate;
  }

  bool _isPreferredGroundingCandidate(Map<String, dynamic> candidate) {
    if (candidate['focused'] == true) {
      return true;
    }
    final role = _stringValue(candidate['role']).toLowerCase();
    final subrole = _stringValue(candidate['subrole']).toLowerCase();
    final roleText = '$role $subrole';
    return _groundingPreferredRoleTokens.any(
      (token) => roleText.contains(token),
    );
  }

  bool _hasPreferredRole(List<Map<String, dynamic>> candidates) {
    return candidates.any(_isPreferredGroundingCandidate);
  }

  String _visionNextAction({
    required bool captureOk,
    required bool imageAttached,
    required Map<String, dynamic> capture,
    int? displayCount,
    required String target,
    required String spaceScope,
    required Map<String, dynamic>? windowsResult,
  }) {
    final captureNextAction = capture['nextAction'];
    if (!captureOk || !imageAttached) {
      if (captureNextAction is String && captureNextAction.isNotEmpty) {
        return captureNextAction;
      }
      return 'Resolve the observation failure, then run computer_vision_observe again.';
    }
    final base =
        'Use the attached screenshot, elementGrounding candidates, and actionProposalPolicy to decide whether to answer, observe again, or request an approved computer-use action with target metadata and exact text when required.';
    if (target == 'display' && (displayCount ?? 0) > 1) {
      return '$base If the target is on another display, use the displayId from the displays result and observe again with display_id.';
    }
    if (spaceScope == 'all_spaces' ||
        _windowResultHasInactiveSpaceWindows(windowsResult)) {
      return '$base For macOS Spaces, windows outside the active Space may need computer_focus_window or an approved computer_press_key Control-Left/Right Space switch, then observe again before any input action.';
    }
    return base;
  }

  static const List<String> _groundingPreferredRoleTokens = [
    'button',
    'checkbox',
    'radio',
    'textfield',
    'text field',
    'searchfield',
    'search field',
    'combobox',
    'combo box',
    'popup',
    'pop up',
    'menuitem',
    'menu item',
    'link',
    'tab',
    'cell',
    'row',
  ];

  static final List<String> _visionAllowedNextTools = List.unmodifiable([
    'computer_vision_observe',
    'computer_accessibility_snapshot',
    'computer_list_displays',
    'computer_list_windows',
    'computer_screenshot',
    'computer_screenshot_window',
    'computer_focus_window',
    'computer_move_mouse',
    'computer_click',
    'computer_drag',
    'computer_scroll',
    'computer_type_text',
    'computer_press_key',
    'computer_start_system_audio_recording',
    'computer_stop_system_audio_recording',
  ]);

  static final List<String> _visionApprovalRequiredTools = List.unmodifiable(
    _visionAllowedNextTools.where(
      MacosComputerUseToolPolicy.requiresUserApproval,
    ),
  );

  static final List<String> _visionArmingRequiredTools = List.unmodifiable(
    _visionAllowedNextTools.where(
      MacosComputerUseToolPolicy.requiresSmokeArming,
    ),
  );

  Future<String> _invokeJson(
    String method, [
    Map<String, dynamic>? arguments,
  ]) async {
    if (!Platform.isMacOS) {
      return jsonEncode({
        'ok': false,
        'code': 'unsupported_platform',
        'error': 'macOS computer use tools are only available on macOS.',
      });
    }

    try {
      final result = await _invokeMap(method, arguments);
      return jsonEncode(_withNextAction(result));
    } on MissingPluginException {
      return jsonEncode({
        'ok': false,
        'code': 'plugin_unavailable',
        'error': 'The macOS computer use plugin is not registered.',
      });
    } on PlatformException catch (error) {
      appLog('[ComputerUse] $method failed: $error');
      return jsonEncode(
        _withNextAction({
          'ok': false,
          'code': error.code,
          'error': error.message ?? error.toString(),
          if (error.details != null) 'details': error.details,
        }),
      );
    }
  }

  Future<Map<String, dynamic>> _invokeMap(
    String method, [
    Map<String, dynamic>? arguments,
  ]) async {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      method,
      arguments,
    );
    return result ?? const <String, dynamic>{};
  }

  Future<String> _invokeTransportJson(Future<String> Function() invoke) async {
    final raw = await invoke();
    final decoded = _decodeMap(raw);
    if (decoded == null) {
      return raw;
    }
    return jsonEncode(_withNextAction(decoded));
  }

  Map<String, dynamic>? _decodeMap(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> _withNextAction(Map<String, dynamic> result) {
    final code = result['code'];
    if (code is! String || result.containsKey('nextAction')) {
      return result;
    }
    final nextAction = _nextActionForCode(code, result);
    if (nextAction == null) {
      return result;
    }
    return {...result, 'nextAction': nextAction};
  }

  String? _nextActionForCode(String code, Map<String, dynamic> result) {
    final permissionOwner = permissionBackendInfo.permissionOwnerName;
    return switch (code) {
      'helper_unreachable' => _helperUnreachableNextAction(result),
      'helper_not_installed' =>
        'Build Caverno with the bundled Caverno Computer Use helper, then launch it from the permissions panel.',
      'accessibility_denied' =>
        'Open System Settings > Privacy & Security > Accessibility, grant $permissionOwner, then refresh permissions.',
      'screen_capture_unavailable' || 'screenshot_failed' =>
        'Open System Settings > Privacy & Security > Screen & System Audio Recording, grant $permissionOwner, then refresh permissions.',
      _ => null,
    };
  }

  String _helperUnreachableNextAction(Map<String, dynamic> result) {
    final details = result['details'];
    final helperRunning =
        result['helperRunning'] == true ||
        (details is Map && details['helperRunning'] == true);
    final helperDiagnostics = details is Map
        ? details['helperSharedDiagnostics']
        : result['helperSharedDiagnostics'];
    if (helperRunning &&
        helperDiagnostics is Map &&
        helperDiagnostics['listenerStarted'] == true &&
        helperDiagnostics['lastHelperIpcRequest'] == null) {
      return 'Caverno Computer Use is running and its listener is started, but no DNC request was recorded. Restart Caverno Computer Use, then retry IPC readiness.';
    }
    if (helperRunning) {
      return 'Caverno Computer Use is running, but IPC did not respond. Restart Caverno Computer Use, then retry IPC readiness.';
    }
    return 'Launch ${MacosComputerUseBackends.helperDisplayName}, then refresh permissions.';
  }
}
