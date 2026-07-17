import 'dart:convert';

import '../../../../core/services/macos_computer_use_service.dart';
import '../../domain/entities/mcp_tool_entity.dart';
import 'mcp_tool_result_normalizer.dart';

/// Exposes Computer Use tools and executes post-approval service operations.
final class BuiltInComputerUseToolHandler {
  BuiltInComputerUseToolHandler({MacosComputerUseService? computerUseService})
    : _computerUseService = computerUseService;

  static const List<String> toolNames = <String>[
    'computer_get_permissions',
    'computer_request_permissions',
    'computer_open_system_settings',
    'computer_vision_observe',
    'computer_accessibility_snapshot',
    'computer_list_displays',
    'computer_screenshot',
    'computer_list_windows',
    'computer_focus_window',
    'computer_screenshot_window',
    'computer_move_mouse',
    'computer_click',
    'computer_drag',
    'computer_scroll',
    'computer_type_text',
    'computer_press_key',
    'computer_switch_space',
    'computer_start_system_audio_recording',
    'computer_stop_system_audio_recording',
  ];

  final MacosComputerUseService? _computerUseService;

  bool get isAvailable => _computerUseService?.isAvailable ?? false;

  List<Map<String, dynamic>> get definitions => _computerUseTools;

  /// Reserves the complete Computer Use namespace, including unknown aliases.
  bool handles(String name) => name.startsWith('computer_');

  Future<McpToolResult> execute({
    required String name,
    required Map<String, dynamic> arguments,
  }) async {
    final service = _computerUseService;
    if (service == null || !service.isAvailable) {
      return McpToolResultNormalizer.failure(
        toolName: name,
        errorMessage: 'macOS computer use tools are unavailable',
      );
    }

    final result = await _executeComputerUseTool(service, name, arguments);
    return McpToolResultNormalizer.fromOkPayload(
      toolName: name,
      result: result,
      fallbackErrorMessage: 'Computer use tool failed',
    );
  }

  Future<String> _executeComputerUseTool(
    MacosComputerUseService service,
    String name,
    Map<String, dynamic> arguments,
  ) {
    return switch (name) {
      'computer_get_permissions' => service.getPermissions(),
      'computer_request_permissions' => service.requestPermissions(
        accessibility: arguments['accessibility'] as bool? ?? true,
        screenCapture:
            arguments['screen_capture'] as bool? ??
            arguments['screenCapture'] as bool? ??
            true,
      ),
      'computer_open_system_settings' => service.openSystemSettings(
        section: arguments['section'] as String? ?? 'privacy',
      ),
      'computer_vision_observe' => service.visionObserve(arguments),
      'computer_accessibility_snapshot' => service.accessibilitySnapshot(
        arguments,
      ),
      'computer_list_displays' => service.listDisplays(arguments),
      'computer_list_windows' => service.listWindows(arguments),
      'computer_focus_window' => service.focusWindow(arguments),
      'computer_screenshot' => service.screenshot(arguments),
      'computer_screenshot_window' => service.screenshotWindow(arguments),
      'computer_move_mouse' => service.moveMouse(arguments),
      'computer_click' => service.click(arguments),
      'computer_drag' => service.drag(arguments),
      'computer_scroll' => service.scroll(arguments),
      'computer_type_text' => service.typeText(arguments),
      'computer_switch_space' => service.switchSpace(arguments),
      'computer_press_key' => service.pressKey(arguments),
      'computer_start_system_audio_recording' =>
        service.startSystemAudioRecording(arguments),
      'computer_stop_system_audio_recording' =>
        service.stopSystemAudioRecording(),
      _ => Future.value(
        jsonEncode({
          'ok': false,
          'code': 'tool_not_available',
          'error': 'No matching computer use tool is available: $name',
        }),
      ),
    };
  }

  static List<Map<String, dynamic>> get _computerUseTools => [
    {
      'type': 'function',
      'function': {
        'name': 'computer_get_permissions',
        'description':
            'Check macOS Accessibility, Screen Recording, and system audio recording availability for computer-use tools.',
        'parameters': {'type': 'object', 'properties': {}, 'required': []},
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'computer_request_permissions',
        'description':
            'Ask macOS to open prompts for Accessibility and/or Screen Recording permissions required by computer-use tools.',
        'parameters': {
          'type': 'object',
          'properties': {
            'accessibility': {
              'type': 'boolean',
              'description': 'Request Accessibility permission.',
            },
            'screen_capture': {
              'type': 'boolean',
              'description': 'Request Screen Recording permission.',
            },
          },
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'computer_open_system_settings',
        'description':
            'Open the relevant macOS Privacy & Security pane for granting Accessibility or Screen Recording permissions. The user must still grant access manually.',
        'parameters': {
          'type': 'object',
          'properties': {
            'section': {
              'type': 'string',
              'enum': ['accessibility', 'screen_recording', 'privacy'],
              'description':
                  'System Settings section to open. Use screen_recording for Screen & System Audio Recording.',
            },
          },
          'required': ['section'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'computer_vision_observe',
        'description':
            'Observe the macOS desktop for a vision LLM loop. Returns permission status, display inventory, optional visible-window metadata, one display or window screenshot as image content, coordinate guidance, and the approved next computer-use tool surface. This tool is read-only.',
        'parameters': {
          'type': 'object',
          'properties': {
            'target': {
              'type': 'string',
              'enum': ['display', 'window', 'front_window'],
              'description':
                  'Observation target. Use window with window_id for a known window, front_window for the first visible non-Caverno window, or display for the full display.',
            },
            'window_id': {
              'type': 'integer',
              'description':
                  'Window ID from computer_list_windows. Required when target is window.',
            },
            'display_id': {
              'type': 'integer',
              'description':
                  'Optional CGDirectDisplayID from computer_list_displays. Used when target is display.',
            },
            'max_width': {
              'type': 'integer',
              'description':
                  'Optional maximum PNG width to reduce tokens. Defaults to 900.',
            },
            'include_windows': {
              'type': 'boolean',
              'description':
                  'Include visible-window metadata. Defaults to true.',
            },
            'space_scope': {
              'type': 'string',
              'enum': ['active_space', 'all_spaces'],
              'description':
                  'macOS Spaces scope for window metadata. Use all_spaces when the target app may be on another desktop; input still requires observing the active Space first.',
            },
            'include_displays': {
              'type': 'boolean',
              'description':
                  'Include display inventory metadata. Defaults to true.',
            },
            'include_accessibility': {
              'type': 'boolean',
              'description':
                  'Include accessibility-derived candidate element metadata for window observations. Defaults to true.',
            },
            'max_candidate_elements': {
              'type': 'integer',
              'description':
                  'Maximum candidate elements to expose in elementGrounding. Defaults to 12.',
            },
            'max_accessibility_elements': {
              'type': 'integer',
              'description':
                  'Maximum accessibility elements to read before selecting candidates. Defaults to 50.',
            },
            'max_accessibility_depth': {
              'type': 'integer',
              'description':
                  'Maximum accessibility tree depth to read for candidate selection. Defaults to 4.',
            },
          },
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'computer_accessibility_snapshot',
        'description':
            'Read a bounded macOS Accessibility snapshot for the front window or a selected window. Returns roles, safe labels, frames, enabled/focused state, child counts, and redaction metadata without taking any desktop action.',
        'parameters': {
          'type': 'object',
          'properties': {
            'target': {
              'type': 'string',
              'enum': ['front_window', 'window'],
              'description':
                  'Snapshot target. Use front_window for the first visible non-Caverno window or window with window_id for a known window.',
            },
            'window_id': {
              'type': 'integer',
              'description':
                  'Window ID from computer_list_windows. Required when target is window.',
            },
            'max_depth': {
              'type': 'integer',
              'description':
                  'Maximum accessibility tree depth to traverse. Defaults to 4 and is capped by the helper.',
            },
            'max_elements': {
              'type': 'integer',
              'description':
                  'Maximum number of elements to return. Defaults to 80 and is capped by the helper.',
            },
            'label_max_characters': {
              'type': 'integer',
              'description':
                  'Maximum safe label length per element before truncation. Defaults to 120.',
            },
          },
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'computer_list_displays',
        'description':
            'List macOS displays with display IDs, indexes, names, point bounds, pixel sizes, and main-display status. Use this before selecting a non-main display for screenshots or desktop actions.',
        'parameters': {
          'type': 'object',
          'properties': {
            'display_id': {
              'type': 'integer',
              'description':
                  'Optional CGDirectDisplayID to validate a selected display.',
            },
            'display_index': {
              'type': 'integer',
              'description':
                  'Optional zero-based display index to validate a selected display.',
            },
          },
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'computer_screenshot',
        'description':
            'Capture a macOS display screenshot for visual inspection. Use returned screenshot pixel coordinates for computer input tools.',
        'parameters': {
          'type': 'object',
          'properties': {
            'display_id': {
              'type': 'integer',
              'description':
                  'Optional CGDirectDisplayID from computer_list_displays. Defaults to the main display.',
            },
            'max_width': {
              'type': 'integer',
              'description': 'Optional maximum PNG width to reduce tokens.',
            },
          },
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'computer_list_windows',
        'description':
            'List macOS application windows with window IDs, app names, titles, bounds, and macOS Spaces visibility status. Prefer this before focusing or capturing a specific app window.',
        'parameters': {
          'type': 'object',
          'properties': {
            'include_current_app': {
              'type': 'boolean',
              'description':
                  'Include Caverno windows in the result. Defaults to false.',
            },
            'max_windows': {
              'type': 'integer',
              'description': 'Maximum number of windows to return.',
            },
            'space_scope': {
              'type': 'string',
              'enum': ['active_space', 'all_spaces'],
              'description':
                  'Use active_space for the current macOS Space, or all_spaces for best-effort discovery across Spaces.',
            },
            'include_hidden': {
              'type': 'boolean',
              'description':
                  'Include hidden, minimized, or non-active-Space windows when supported by macOS. Defaults to true for all_spaces.',
            },
          },
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'computer_focus_window',
        'description':
            'Bring a specific macOS window to the foreground by window_id. Optionally focus an element_id from the latest elementGrounding candidates. Requires Accessibility permission.',
        'parameters': {
          'type': 'object',
          'properties': {
            'window_id': {
              'type': 'integer',
              'description':
                  'Window ID from computer_list_windows or computer_screenshot_window.',
            },
            ..._computerElementTargetProperties,
            ..._computerActionTargetMetadataProperties,
            'reason': {'type': 'string'},
          },
          'required': ['window_id'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'computer_screenshot_window',
        'description':
            'Capture a specific macOS window screenshot. Use returned window pixel coordinates and window_id for follow-up computer input tools.',
        'parameters': {
          'type': 'object',
          'properties': {
            'window_id': {
              'type': 'integer',
              'description': 'Window ID from computer_list_windows.',
            },
            'max_width': {
              'type': 'integer',
              'description': 'Optional maximum PNG width to reduce tokens.',
            },
          },
          'required': ['window_id'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'computer_move_mouse',
        'description':
            'Move the macOS pointer to screenshot pixel coordinates.',
        'parameters': _computerPointParameters(required: ['x', 'y']),
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'computer_click',
        'description':
            'Click an element_id from the latest elementGrounding candidates, or fall back to screenshot pixel coordinates. Requires explicit user approval in Caverno before execution.',
        'parameters': {
          ..._computerPointParameters(),
          'properties': {
            ..._computerPointProperties,
            ..._computerElementTargetProperties,
            'button': {
              'type': 'string',
              'enum': ['left', 'right', 'middle'],
              'description': 'Mouse button. Defaults to left.',
            },
            'click_count': {
              'type': 'integer',
              'description': 'Number of clicks, from 1 to 3.',
            },
            'reason': {
              'type': 'string',
              'description': 'Why this click is needed.',
            },
            ..._computerActionTargetMetadataProperties,
          },
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'computer_drag',
        'description':
            'Drag from one screenshot pixel coordinate to another. Requires explicit user approval in Caverno before execution.',
        'parameters': {
          'type': 'object',
          'properties': {
            ..._computerDisplayProperties,
            'from_x': {'type': 'number'},
            'from_y': {'type': 'number'},
            'to_x': {'type': 'number'},
            'to_y': {'type': 'number'},
            'duration_ms': {
              'type': 'integer',
              'description': 'Drag duration in milliseconds.',
            },
            ..._computerActionTargetMetadataProperties,
            'reason': {'type': 'string'},
          },
          'required': ['from_x', 'from_y', 'to_x', 'to_y'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'computer_scroll',
        'description':
            'Scroll the active macOS target, optionally after moving to screenshot pixel coordinates.',
        'parameters': {
          'type': 'object',
          'properties': {
            ..._computerPointProperties,
            'delta_x': {'type': 'integer'},
            'delta_y': {
              'type': 'integer',
              'description': 'Positive scrolls up, negative scrolls down.',
            },
            ..._computerActionTargetMetadataProperties,
            'reason': {'type': 'string'},
          },
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'computer_type_text',
        'description':
            'Type text into an element_id from the latest elementGrounding candidates, or into the currently focused macOS UI element when no element target is provided. Requires explicit user approval in Caverno before execution.',
        'parameters': {
          'type': 'object',
          'properties': {
            'text': {'type': 'string'},
            ..._computerWindowElementTargetProperties,
            ..._computerActionTargetMetadataProperties,
            'reason': {'type': 'string'},
          },
          'required': ['text'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'computer_press_key',
        'description':
            'Press a keyboard key, optionally with modifiers such as command, shift, option, or control. Use computer_switch_space for macOS Spaces switching.',
        'parameters': {
          'type': 'object',
          'properties': {
            'key': {'type': 'string'},
            'modifiers': {
              'type': 'array',
              'items': {'type': 'string'},
            },
            ..._computerActionTargetMetadataProperties,
            'reason': {'type': 'string'},
          },
          'required': ['key'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'computer_switch_space',
        'description':
            'Switch to an adjacent macOS Space with Control-Left or Control-Right. Requires explicit user approval and must be followed by computer_vision_observe before pointer or keyboard input.',
        'parameters': {
          'type': 'object',
          'properties': {
            'direction': {
              'type': 'string',
              'enum': ['next', 'previous'],
              'description':
                  'Use next for Control-Right, or previous for Control-Left.',
            },
            'reason': {
              'type': 'string',
              'description': 'Why switching Spaces is needed.',
            },
          },
          'required': ['direction'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'computer_start_system_audio_recording',
        'description':
            'Start recording macOS system audio to a CAF file via ScreenCaptureKit. Requires explicit user approval in Caverno before execution.',
        'parameters': {
          'type': 'object',
          'properties': {
            'output_path': {
              'type': 'string',
              'description': 'Optional absolute CAF output path.',
            },
            'exclude_current_process_audio': {
              'type': 'boolean',
              'description':
                  'Exclude Caverno audio from the recording. Defaults to true.',
            },
            'reason': {'type': 'string'},
          },
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'computer_stop_system_audio_recording',
        'description':
            'Stop the active macOS system audio recording and return the output file path.',
        'parameters': {'type': 'object', 'properties': {}, 'required': []},
      },
    },
  ];

  static Map<String, dynamic> _computerPointParameters({
    List<String> required = const [],
  }) {
    return {
      'type': 'object',
      'properties': _computerPointProperties,
      if (required.isNotEmpty) 'required': required,
    };
  }

  static Map<String, dynamic> get _computerPointProperties => {
    ..._computerDisplayProperties,
    'x': {
      'type': 'number',
      'description': 'X coordinate in screenshot pixels from the top-left.',
    },
    'y': {
      'type': 'number',
      'description': 'Y coordinate in screenshot pixels from the top-left.',
    },
  };

  static Map<String, dynamic> get _computerDisplayProperties => {
    'window_id': {
      'type': 'integer',
      'description':
          'Optional window ID from computer_list_windows or computer_screenshot_window. When set, x/y are interpreted as window screenshot pixels.',
    },
    'display_id': {
      'type': 'integer',
      'description':
          'Optional display ID from computer_list_displays, computer_vision_observe, or computer_screenshot.',
    },
    'source_width': {
      'type': 'number',
      'description': 'Width of the screenshot used to choose coordinates.',
    },
    'source_height': {
      'type': 'number',
      'description': 'Height of the screenshot used to choose coordinates.',
    },
    'coordinate_space': {
      'type': 'string',
      'description':
          'Coordinate space from computer_vision_observe, such as window_pixels or display_pixels.',
    },
    'vision_observation_id': {
      'type': 'string',
      'description':
          'Observation ID from the latest computer_vision_observe result used to choose this action.',
    },
  };

  static Map<String, dynamic> get _computerElementTargetProperties => {
    'element_id': {
      'type': 'string',
      'description':
          'Optional execution target elementId from the latest computer_vision_observe elementGrounding candidateElements.',
    },
    'max_accessibility_elements': {
      'type': 'integer',
      'description':
          'Maximum accessibility elements to scan while resolving element_id. Defaults to 80.',
    },
    'max_accessibility_depth': {
      'type': 'integer',
      'description':
          'Maximum accessibility tree depth to scan while resolving element_id. Defaults to 4.',
    },
  };

  static Map<String, dynamic> get _computerWindowElementTargetProperties => {
    'window_id': {
      'type': 'integer',
      'description':
          'Window ID from the latest computer_vision_observe or computer_list_windows result. Required when element_id is provided.',
    },
    ..._computerElementTargetProperties,
  };

  static Map<String, dynamic> get _computerActionTargetMetadataProperties => {
    'target': {
      'type': 'object',
      'description':
          'Optional visible UI target metadata used only for Caverno approval. Mark public posting, sending, submitting, or publishing controls with risk=public_action. Mark secure fields, credential prompts, payment flows, and destructive controls with their matching risk.',
      'properties': {
        'label': {
          'type': 'string',
          'description': 'Visible label or accessible name of the target.',
        },
        'role': {
          'type': 'string',
          'description': 'Visible or accessibility role of the target.',
        },
        'appName': {
          'type': 'string',
          'description':
              'Visible application name from the latest observation or window list.',
        },
        'appBundleId': {
          'type': 'string',
          'description':
              'Application bundle identifier when available from the latest observation or window list.',
        },
        'windowTitle': {
          'type': 'string',
          'description':
              'Window title from the latest observation or window list.',
        },
        'windowId': {
          'type': 'integer',
          'description':
              'Window ID from the latest observation or window list.',
        },
        'elementId': {
          'type': 'string',
          'description':
              'Optional elementId from the latest computer_vision_observe elementGrounding candidates.',
        },
        'action': {
          'type': 'string',
          'description': 'Intended action, such as click, submit, or publish.',
        },
        'risk': {
          'type': 'string',
          'enum': [
            'input',
            'public_action',
            'secure_field',
            'credential',
            'payment',
            'destructive',
            'sensitive',
            'unknown',
          ],
          'description':
              'Use public_action for controls that post, send, submit, publish, or otherwise change external state. Use secure_field, credential, payment, or destructive for targets that should be blocked or manually handled.',
        },
      },
    },
  };
}
