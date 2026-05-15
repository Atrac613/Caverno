import 'dart:convert';

import 'package:caverno/core/services/macos_computer_use_service.dart';
import 'package:caverno/core/services/macos_computer_use_setup.dart';
import 'package:caverno/core/services/macos_computer_use_transport.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('uses the helper transport for permission status', () async {
    final transport = _FakePermissionTransport(
      permissions: {
        'ok': true,
        'backend': 'helper',
        'helperReachable': true,
        'accessibilityGranted': true,
        'screenCaptureGranted': false,
        'systemAudioRecordingSupported': true,
      },
    );
    final service = MacosComputerUseService(permissionTransport: transport);

    final permissions =
        jsonDecode(await service.getPermissions()) as Map<String, dynamic>;

    expect(service.permissionBackendInfo, MacosComputerUseBackends.helperIpc);
    expect(transport.calledMethods, ['getPermissions']);
    expect(permissions, containsPair('backend', 'helper'));
    expect(permissions, containsPair('helperReachable', true));
    expect(permissions, containsPair('accessibilityGranted', true));
  });

  test(
    'adds a helper launch next action when the helper is unreachable',
    () async {
      final service = MacosComputerUseService(
        permissionTransport: _FakePermissionTransport(
          permissions: {
            'ok': false,
            'backend': 'helper',
            'helperReachable': false,
            'code': 'helper_unreachable',
            'error': 'Caverno Computer Use did not respond.',
          },
        ),
      );

      final permissions =
          jsonDecode(await service.getPermissions()) as Map<String, dynamic>;

      expect(permissions, containsPair('code', 'helper_unreachable'));
      expect(
        permissions,
        containsPair(
          'nextAction',
          'Launch Caverno Computer Use, then refresh permissions.',
        ),
      );
    },
  );

  test(
    'adds a restart next action when a running helper misses IPC requests',
    () async {
      final service = MacosComputerUseService(
        permissionTransport: _FakePermissionTransport(
          permissions: {
            'ok': false,
            'backend': 'helper',
            'helperReachable': false,
            'code': 'helper_unreachable',
            'error': 'Caverno Computer Use did not respond.',
            'details': {
              'helperRunning': true,
              'helperSharedDiagnostics': {
                'listenerStarted': true,
                'helperIpcEventCount': 0,
              },
            },
          },
        ),
      );

      final permissions =
          jsonDecode(await service.getPermissions()) as Map<String, dynamic>;

      expect(permissions, containsPair('code', 'helper_unreachable'));
      expect(
        permissions,
        containsPair(
          'nextAction',
          'Caverno Computer Use is running and its listener is started, but no DNC request was recorded. Restart Caverno Computer Use, then retry IPC readiness.',
        ),
      );
    },
  );

  test('waits for helper IPC readiness with retry metadata', () async {
    final transport = _FakePermissionTransport(
      permissions: {
        'ok': true,
        'backend': 'helper',
        'helperReachable': true,
        'accessibilityGranted': true,
        'screenCaptureGranted': true,
        'systemAudioRecordingSupported': true,
      },
    );
    final service = MacosComputerUseService(permissionTransport: transport);

    final result =
        jsonDecode(
              await service.waitForHelperIpcReady(
                attempts: 1,
                delay: Duration.zero,
              ),
            )
            as Map<String, dynamic>;

    expect(result, containsPair('ipcReady', true));
    expect(result, containsPair('attempts', 1));
    expect(transport.calledMethods, ['ping']);
  });

  test('launches the helper before guiding permission requests', () async {
    final transport = _FakePermissionTransport(
      permissions: {
        'ok': true,
        'backend': 'helper',
        'helperReachable': true,
        'accessibilityGranted': false,
        'screenCaptureGranted': false,
        'systemAudioRecordingSupported': true,
      },
    );
    final service = MacosComputerUseService(permissionTransport: transport);

    final result =
        jsonDecode(
              await service.requestPermissions(
                accessibility: true,
                screenCapture: false,
              ),
            )
            as Map<String, dynamic>;

    expect(transport.calledMethods, [
      'launchHelper',
      'ping',
      'showPermissionOverlay:accessibility',
      'getPermissions',
    ]);
    expect(result, containsPair('helper', isA<Map<String, dynamic>>()));
    expect(result, containsPair('helperReady', isA<Map<String, dynamic>>()));
    expect(result, containsPair('current', isA<Map<String, dynamic>>()));
  });

  test(
    'routes LaunchAgent registration through the helper transport',
    () async {
      final transport = _FakePermissionTransport(
        permissions: const <String, dynamic>{'ok': true},
      );
      final service = MacosComputerUseService(permissionTransport: transport);

      final registered =
          jsonDecode(await service.registerXpcLaunchAgent())
              as Map<String, dynamic>;
      final unregistered =
          jsonDecode(await service.unregisterXpcLaunchAgent())
              as Map<String, dynamic>;

      expect(transport.calledMethods, [
        'registerXpcLaunchAgent',
        'unregisterXpcLaunchAgent',
      ]);
      expect(registered, containsPair('xpcLaunchAgentStatus', 'enabled'));
      expect(
        unregistered,
        containsPair('xpcLaunchAgentStatus', 'not_registered'),
      );
    },
  );

  test('routes permission overlays through the helper transport', () async {
    final transport = _FakePermissionTransport(
      permissions: const <String, dynamic>{'ok': true},
    );
    final service = MacosComputerUseService(permissionTransport: transport);

    final result =
        jsonDecode(
              await service.showPermissionOverlay(
                permission: 'screenRecording',
              ),
            )
            as Map<String, dynamic>;

    expect(transport.calledMethods, [
      'launchHelper',
      'ping',
      'showPermissionOverlay:screenRecording',
    ]);
    expect(result, containsPair('permission', 'screenRecording'));
    expect(result, containsPair('overlayRequested', true));
    expect(result, containsPair('draggableTileReady', true));
    expect(result, containsPair('helperUi', isA<Map<String, dynamic>>()));
  });

  test(
    'routes onboarding permission flows through the helper transport',
    () async {
      final transport = _FakePermissionTransport(
        permissions: const <String, dynamic>{'ok': true},
      );
      final service = MacosComputerUseService(permissionTransport: transport);

      final result =
          jsonDecode(
                await service.startOnboardingPermissionFlow(
                  permission: 'screenRecording',
                ),
              )
              as Map<String, dynamic>;

      expect(transport.calledMethods, [
        'launchHelper',
        'ping',
        'startOnboardingPermissionFlow:screenRecording',
      ]);
      expect(result, containsPair('permission', 'screenRecording'));
      expect(result, containsPair('onboardingFlowRequested', true));
      expect(result, containsPair('lastOnboardingTransition', isA<Map>()));
      expect(result, containsPair('helperUi', isA<Map<String, dynamic>>()));
    },
  );

  test('packages display screenshots for vision observations', () async {
    final service = _FakeVisionMacosComputerUseService();

    final result =
        jsonDecode(
              await service.visionObserve(const {
                'target': 'display',
                'max_width': 640,
              }),
            )
            as Map<String, dynamic>;

    expect(service.calledMethods, [
      'getPermissions',
      'listDisplays',
      'listWindows',
      'screenshot',
    ]);
    expect(result, containsPair('ok', true));
    expect(
      result,
      containsPair('schemaName', 'macos_computer_use_vision_observation'),
    );
    expect(result['observationId'], isA<String>());
    expect(result, containsPair('imageBase64', 'display-image'));
    expect(
      result['allowedNextTools'],
      contains('computer_accessibility_snapshot'),
    );
    expect(result['allowedNextTools'], contains('computer_click'));
    expect(result['allowedNextTools'], contains('computer_switch_space'));
    expect(result['approvalRequiredTools'], contains('computer_click'));
    expect(result['approvalRequiredTools'], contains('computer_switch_space'));
    expect(result['armingRequiredTools'], contains('computer_type_text'));
    expect(result['armingRequiredTools'], contains('computer_switch_space'));
    expect(result['coordinateGuidance'], containsPair('sourceWidth', 640));
    expect(result['displays'], containsPair('count', 2));
    expect(result['target'], containsPair('displayId', 1));
    expect(result['nextAction'], contains('observe again with display_id'));
    expect(result['elementGrounding'], containsPair('status', 'skipped'));
    expect(
      result['elementGrounding'],
      containsPair('code', 'window_target_required'),
    );
    expect(result['nextAction'], contains('actionProposalPolicy'));
    expect(result['nextAction'], contains('elementGrounding'));
    final actionProposalPolicy =
        result['actionProposalPolicy'] as Map<String, dynamic>;
    expect(
      actionProposalPolicy,
      containsPair('schemaName', 'macos_computer_use_action_proposal_policy'),
    );
    expect(
      jsonEncode(actionProposalPolicy),
      contains('target.risk=public_action'),
    );
    final productionActionPolicy =
        result['productionActionPolicy'] as Map<String, dynamic>;
    expect(
      productionActionPolicy,
      containsPair('schemaName', 'macos_computer_use_production_action_policy'),
    );
    expect(
      productionActionPolicy['phaseOrder'],
      containsAll([
        'observe',
        'approval_packet',
        'action_time_confirmation',
        'emergency_stop_available',
        'execution_result_intake',
        'post_action_review',
      ]),
    );
    expect(
      actionProposalPolicy['productionActionPolicy'],
      containsPair('publicActionSeparateApprovalRequired', true),
    );
    final toolPolicies = actionProposalPolicy['toolPolicies'] as List<dynamic>;
    final snapshotPolicy = toolPolicies
        .cast<Map<String, dynamic>>()
        .singleWhere(
          (policy) => policy['toolName'] == 'computer_accessibility_snapshot',
        );
    expect(snapshotPolicy['allowedAsObserveOnlyProposal'], isTrue);
    expect(snapshotPolicy['requiresUserApproval'], isFalse);
    final clickPolicy = toolPolicies.cast<Map<String, dynamic>>().singleWhere(
      (policy) => policy['toolName'] == 'computer_click',
    );
    expect(clickPolicy['boundaries'], contains('target'));
    final typeTextPolicy = toolPolicies
        .cast<Map<String, dynamic>>()
        .singleWhere((policy) => policy['toolName'] == 'computer_type_text');
    expect(typeTextPolicy['boundaries'], containsAll(['target', 'exactText']));
    expect(typeTextPolicy['blockerCodes'], contains('exact_text_missing'));
    final switchSpacePolicy = toolPolicies
        .cast<Map<String, dynamic>>()
        .singleWhere((policy) => policy['toolName'] == 'computer_switch_space');
    expect(switchSpacePolicy['requiresUserApproval'], isTrue);
    expect(switchSpacePolicy['requiresTargetApproval'], isFalse);
    expect(switchSpacePolicy['blockerCodes'], isEmpty);
  });

  test(
    'resolves the first visible window for front-window vision observations',
    () async {
      final service = _FakeVisionMacosComputerUseService();

      final result =
          jsonDecode(
                await service.visionObserve(const {
                  'target': 'front_window',
                  'include_windows': true,
                }),
              )
              as Map<String, dynamic>;

      expect(service.calledMethods, [
        'getPermissions',
        'listDisplays',
        'listWindows',
        'screenshotWindow',
        'accessibilitySnapshot',
      ]);
      expect(result, containsPair('ok', true));
      expect(result['imageBase64'], 'window-image');
      expect(result['target'], containsPair('resolved', 'window'));
      expect(result['target'], containsPair('windowId', 42));
      expect(result['coordinateGuidance'], containsPair('windowId', 42));
      final elementGrounding =
          result['elementGrounding'] as Map<String, dynamic>;
      expect(elementGrounding, containsPair('status', 'ready'));
      expect(elementGrounding, containsPair('windowId', 42));
      expect(
        elementGrounding,
        containsPair('schemaName', 'macos_computer_use_element_grounding'),
      );
      expect(elementGrounding['candidateElementCount'], 2);
      final candidates = elementGrounding['candidateElements'] as List<dynamic>;
      expect(candidates.first, containsPair('elementId', 'ax-0002'));
      expect(candidates.first, containsPair('role', 'AXButton'));
      expect(candidates.first, containsPair('label', 'Submit'));
      expect(
        elementGrounding['redaction'],
        containsPair('valuesOmitted', true),
      );
    },
  );

  test('passes macOS Spaces scope through vision observations', () async {
    final service = _FakeVisionMacosComputerUseService();

    final result =
        jsonDecode(
              await service.visionObserve(const {
                'target': 'front_window',
                'space_scope': 'all_spaces',
              }),
            )
            as Map<String, dynamic>;

    expect(
      service.lastListWindowsArguments,
      containsPair('space_scope', 'all_spaces'),
    );
    expect(result['target'], containsPair('spaceScope', 'all_spaces'));
    expect(result['windows'], containsPair('spaceScope', 'all_spaces'));
    expect(result['nextAction'], contains('macOS Spaces'));
    expect(result['nextAction'], contains('computer_switch_space'));
  });

  test('passes selected display IDs through vision observations', () async {
    final service = _FakeVisionMacosComputerUseService();

    final result =
        jsonDecode(
              await service.visionObserve(const {
                'target': 'display',
                'display_id': 2,
                'include_windows': false,
              }),
            )
            as Map<String, dynamic>;

    expect(service.calledMethods, [
      'getPermissions',
      'listDisplays',
      'screenshot',
    ]);
    expect(result['target'], containsPair('displayId', 2));
    expect(result['coordinateGuidance'], containsPair('displayId', 2));
    expect(result['observation'], containsPair('displayId', 2));
  });

  test(
    'promotes target elementId to helper element_id for actions',
    () async {
      const channel = MethodChannel('com.caverno/macos_computer_use');
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return <String, dynamic>{
              'ok': true,
              'method': call.method,
              'arguments': call.arguments,
            };
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });

      final service = MacosComputerUseService();

      await service.click(const {
        'window_id': 42,
        'target': {'elementId': 'ax-0002'},
      });
      await service.typeText(const {
        'text': 'hello',
        'window_id': 42,
        'target': {'elementId': 'ax-0003'},
      });
      await service.focusWindow(const {
        'window_id': 42,
        'target': {'elementId': 'ax-0003'},
      });

      expect(calls.map((call) => call.method), [
        'click',
        'typeText',
        'focusWindow',
      ]);
      expect(calls[0].arguments, containsPair('element_id', 'ax-0002'));
      expect(calls[1].arguments, containsPair('element_id', 'ax-0003'));
      expect(calls[2].arguments, containsPair('element_id', 'ax-0003'));
    },
    skip: !MacosComputerUseService().isAvailable,
  );

  test(
    'switches macOS Spaces through Control arrow keypresses',
    () async {
      const channel = MethodChannel('com.caverno/macos_computer_use');
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return <String, dynamic>{
              'ok': true,
              'method': call.method,
              'arguments': call.arguments,
            };
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });

      final service = MacosComputerUseService();

      final result =
          jsonDecode(await service.switchSpace(const {'direction': 'previous'}))
              as Map<String, dynamic>;

      expect(calls.map((call) => call.method), ['pressKey']);
      expect(calls.single.arguments, containsPair('key', 'left'));
      expect(calls.single.arguments, containsPair('modifiers', ['control']));
      expect(
        result,
        containsPair('schemaName', 'macos_computer_use_space_switch'),
      );
      expect(result, containsPair('direction', 'previous'));
      expect(result, containsPair('requiresPostActionObservation', true));
    },
    skip: !MacosComputerUseService().isAvailable,
  );

  test('rejects invalid macOS Space switch directions before input', () async {
    final service = MacosComputerUseService();

    final result =
        jsonDecode(await service.switchSpace(const {'direction': 'up'}))
            as Map<String, dynamic>;

    expect(result, containsPair('ok', false));
    expect(result, containsPair('code', 'invalid_space_switch_direction'));
  });
}

class _FakeVisionMacosComputerUseService extends MacosComputerUseService {
  final List<String> calledMethods = [];
  Map<String, dynamic>? lastListWindowsArguments;

  @override
  Future<String> getPermissions() async {
    calledMethods.add('getPermissions');
    return jsonEncode({
      'ok': true,
      'accessibilityGranted': true,
      'screenCaptureGranted': true,
      'systemAudioRecordingSupported': true,
    });
  }

  @override
  Future<String> listWindows(Map<String, dynamic> arguments) async {
    calledMethods.add('listWindows');
    lastListWindowsArguments = Map<String, dynamic>.from(arguments);
    final spaceScope = arguments['space_scope'] ?? 'active_space';
    return jsonEncode({
      'ok': true,
      'schemaName': 'macos_computer_use_window_inventory',
      'spaceScope': spaceScope,
      'spaceSupport': {
        'desktopModel': 'macos_spaces',
        'allSpacesBestEffort': spaceScope == 'all_spaces',
      },
      'windows': [
        {
          'windowId': 42,
          'appName': 'Example',
          'title': 'Example Window',
          'bounds': {'x': 10, 'y': 20, 'width': 800, 'height': 600},
          'spaceStatus': spaceScope == 'all_spaces'
              ? 'not_on_active_space_or_hidden'
              : 'active_space_visible',
        },
      ],
    });
  }

  @override
  Future<String> listDisplays(Map<String, dynamic> arguments) async {
    calledMethods.add('listDisplays');
    return jsonEncode({
      'ok': true,
      'schemaName': 'macos_computer_use_display_inventory',
      'count': 2,
      'coordinateSpace': 'screen_points',
      'displays': [
        {
          'displayId': 1,
          'displayIndex': 0,
          'name': 'Main Display',
          'isMain': true,
          'bounds': {'x': 0, 'y': 0, 'width': 1440, 'height': 900},
          'pixelWidth': 1440,
          'pixelHeight': 900,
        },
        {
          'displayId': 2,
          'displayIndex': 1,
          'name': 'Secondary Display',
          'isMain': false,
          'bounds': {'x': 1440, 'y': 0, 'width': 1280, 'height': 720},
          'pixelWidth': 1280,
          'pixelHeight': 720,
        },
      ],
    });
  }

  @override
  Future<String> screenshot(Map<String, dynamic> arguments) async {
    calledMethods.add('screenshot');
    return jsonEncode({
      'ok': true,
      'command': 'screenshot',
      'coordinateSpace': 'screenshot_pixels',
      'width': arguments['max_width'] ?? 900,
      'height': 360,
      'displayId': arguments['display_id'] ?? 1,
      'imageBase64': 'display-image',
      'imageMimeType': 'image/png',
    });
  }

  @override
  Future<String> screenshotWindow(Map<String, dynamic> arguments) async {
    calledMethods.add('screenshotWindow');
    return jsonEncode({
      'ok': true,
      'command': 'screenshotWindow',
      'coordinateSpace': 'window_pixels',
      'width': 900,
      'height': 600,
      'windowId': arguments['window_id'],
      'imageBase64': 'window-image',
      'imageMimeType': 'image/png',
    });
  }

  @override
  Future<String> accessibilitySnapshot(Map<String, dynamic> arguments) async {
    calledMethods.add('accessibilitySnapshot');
    return jsonEncode({
      'ok': true,
      'schemaName': 'macos_computer_use_accessibility_snapshot',
      'schemaVersion': 1,
      'observationId': 'ax-snapshot-1',
      'snapshotId': 'ax-snapshot-1',
      'readOnly': true,
      'window': {'windowId': arguments['window_id']},
      'coordinateSpace': 'screen_points',
      'inputOrigin': 'top_left',
      'bounds': {
        'maxElements': arguments['max_elements'],
        'maxDepth': arguments['max_depth'],
        'labelMaxCharacters': arguments['label_max_characters'],
      },
      'elementCount': 3,
      'truncated': false,
      'truncation': {
        'byElementLimit': false,
        'byDepthLimit': false,
        'labelTruncatedCount': 0,
      },
      'redaction': {
        'policy': 'metadata_only',
        'valuesOmitted': true,
        'selectedTextOmitted': true,
        'rawAttributeValuesOmitted': true,
      },
      'elements': [
        {
          'elementId': 'ax-0001',
          'role': 'AXWindow',
          'label': 'Example Window',
          'frame': {'x': 10, 'y': 20, 'width': 800, 'height': 600},
          'frameKnown': true,
          'enabled': true,
          'enabledKnown': true,
          'focused': false,
          'focusedKnown': true,
          'childCount': 2,
          'redaction': {'valueOmitted': true},
        },
        {
          'elementId': 'ax-0002',
          'parentId': 'ax-0001',
          'role': 'AXButton',
          'label': 'Submit',
          'labelSource': 'title',
          'frame': {'x': 30, 'y': 40, 'width': 120, 'height': 32},
          'frameKnown': true,
          'enabled': true,
          'enabledKnown': true,
          'focused': false,
          'focusedKnown': true,
          'childCount': 0,
          'redaction': {'valueOmitted': true},
        },
        {
          'elementId': 'ax-0003',
          'parentId': 'ax-0001',
          'role': 'AXTextField',
          'label': 'Message',
          'labelSource': 'description',
          'frame': {'x': 30, 'y': 90, 'width': 240, 'height': 32},
          'frameKnown': true,
          'enabled': true,
          'enabledKnown': true,
          'focused': true,
          'focusedKnown': true,
          'childCount': 0,
          'redaction': {'valueOmitted': true},
        },
      ],
    });
  }
}

class _FakePermissionTransport extends MacosComputerUsePermissionTransport {
  _FakePermissionTransport({required this.permissions});

  final Map<String, dynamic> permissions;
  final List<String> calledMethods = [];

  @override
  MacosComputerUseBackendInfo get backendInfo =>
      MacosComputerUseBackends.helperIpc;

  @override
  Future<String> helperStatus() async {
    calledMethods.add('helperStatus');
    return jsonEncode({
      'ok': true,
      'helperInstalled': true,
      'helperRunning': true,
    });
  }

  @override
  Future<String> launchHelper() async {
    calledMethods.add('launchHelper');
    return jsonEncode({'ok': true, 'helperRunning': true});
  }

  @override
  Future<String> restartHelper() async {
    calledMethods.add('restartHelper');
    return jsonEncode({'ok': true, 'helperRunning': true, 'restarted': true});
  }

  @override
  Future<String> terminateHelperForXpcLaunchAgent() async {
    calledMethods.add('terminateHelperForXpcLaunchAgent');
    return jsonEncode({
      'ok': true,
      'helperRunning': false,
      'terminatedForXpcLaunchAgent': true,
    });
  }

  @override
  Future<String> registerXpcLaunchAgent() async {
    calledMethods.add('registerXpcLaunchAgent');
    return jsonEncode({'ok': true, 'xpcLaunchAgentStatus': 'enabled'});
  }

  @override
  Future<String> unregisterXpcLaunchAgent() async {
    calledMethods.add('unregisterXpcLaunchAgent');
    return jsonEncode({'ok': true, 'xpcLaunchAgentStatus': 'not_registered'});
  }

  @override
  Future<String> getPermissions() async {
    calledMethods.add('getPermissions');
    return jsonEncode(permissions);
  }

  @override
  Future<String> openSystemSettings({required String section}) async {
    calledMethods.add('openSystemSettings:$section');
    return jsonEncode({'ok': true, 'section': section});
  }

  @override
  Future<String> showPermissionOverlay({required String permission}) async {
    calledMethods.add('showPermissionOverlay:$permission');
    return jsonEncode({
      'ok': true,
      'permission': permission,
      'settingsOpened': true,
      'overlayRequested': true,
      'overlayShown': false,
      'draggableTileReady': true,
    });
  }

  @override
  Future<String> startOnboardingPermissionFlow({
    required String permission,
  }) async {
    calledMethods.add('startOnboardingPermissionFlow:$permission');
    return jsonEncode({
      'ok': true,
      'permission': permission,
      'onboardingFlowRequested': true,
      'lastOnboardingTransition': {
        'onboardingTransitionStarted': true,
        'transitionSourcePermission': permission,
        'transitionPlaceholderShown': true,
        'transitionAnimationTarget': 'permission_overlay_window',
      },
    });
  }

  @override
  Future<String> ping() async {
    calledMethods.add('ping');
    return jsonEncode({'ok': true, 'message': 'pong'});
  }

  @override
  Future<String> stopAll() async {
    calledMethods.add('stopAll');
    return jsonEncode({'ok': true});
  }
}
