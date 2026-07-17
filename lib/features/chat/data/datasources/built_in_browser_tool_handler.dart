import 'dart:convert';

import '../../../../core/services/browser_session_service.dart';
import '../../domain/entities/mcp_tool_entity.dart';
import 'mcp_tool_result_normalizer.dart';

/// Exposes built-in browser tools and executes approved browser operations.
final class BuiltInBrowserToolHandler {
  BuiltInBrowserToolHandler({BrowserSessionService? browserService})
    : _browserService = browserService;

  static const List<String> toolNames = <String>[
    'browser_open',
    'browser_snapshot',
    'browser_get_content',
    'browser_screenshot',
    'browser_wait',
    'browser_navigate_history',
    'browser_close',
    'browser_fill',
    'browser_click',
    'browser_submit',
    'browser_eval',
    'browser_save_data',
  ];

  final BrowserSessionService? _browserService;

  bool get isAvailable => _browserService?.isAvailable ?? false;

  List<Map<String, dynamic>> get definitions => <Map<String, dynamic>>[
    _browserOpenTool,
    _browserSnapshotTool,
    _browserGetContentTool,
    _browserScreenshotTool,
    _browserWaitTool,
    _browserNavigateHistoryTool,
    _browserCloseTool,
    _browserFillTool,
    _browserClickTool,
    _browserSubmitTool,
    _browserEvalTool,
    _browserSaveDataTool,
  ];

  /// Reserves the complete browser namespace, including unknown aliases.
  bool handles(String name) => name.startsWith('browser_');

  Future<McpToolResult> execute({
    required String name,
    required Map<String, dynamic> arguments,
  }) async {
    final service = _browserService;
    if (service == null || !service.isAvailable) {
      return McpToolResultNormalizer.failure(
        toolName: name,
        errorMessage: 'Built-in browser tools are unavailable',
      );
    }

    final result = await _executeBrowserTool(service, name, arguments);
    return McpToolResultNormalizer.fromOkPayload(
      toolName: name,
      result: result,
      fallbackErrorMessage: 'Browser tool failed',
    );
  }

  Future<String> _executeBrowserTool(
    BrowserSessionService service,
    String name,
    Map<String, dynamic> arguments,
  ) {
    int? readRef() {
      final ref = arguments['ref'];
      if (ref is int) return ref;
      if (ref is num) return ref.toInt();
      if (ref is String) return int.tryParse(ref);
      return null;
    }

    String? readSelector() {
      final selector = (arguments['selector'] as String?)?.trim();
      return (selector == null || selector.isEmpty) ? null : selector;
    }

    return switch (name) {
      'browser_open' => service.openUrl((arguments['url'] as String?) ?? ''),
      'browser_snapshot' => service.snapshot(
        maxElements: (arguments['max_elements'] as num?)?.toInt(),
      ),
      'browser_get_content' => service.getContent(
        format: (arguments['format'] as String?) ?? 'text',
        maxChars: (arguments['max_chars'] as num?)?.toInt(),
      ),
      'browser_screenshot' => service.screenshot(),
      'browser_wait' => service.waitFor(
        selector: readSelector(),
        timeoutMs: (arguments['timeout_ms'] as num?)?.toInt(),
      ),
      'browser_navigate_history' => service.navigateHistory(
        (arguments['direction'] as String?) ?? 'reload',
      ),
      'browser_close' => Future.value(service.closePanel()),
      'browser_fill' => service.fillField(
        ref: readRef(),
        selector: readSelector(),
        value: (arguments['value'] as String?) ?? '',
      ),
      'browser_click' => service.clickElement(
        ref: readRef(),
        selector: readSelector(),
      ),
      'browser_submit' => service.submitForm(selector: readSelector()),
      'browser_eval' => service.evaluateJs(
        (arguments['script'] as String?) ?? '',
      ),
      'browser_save_data' => service.saveData(
        filename: (arguments['filename'] as String?) ?? 'browser_data',
        data: (arguments['data'] as String?) ?? '',
        format: (arguments['format'] as String?) ?? 'json',
        destination: arguments['destination'] as String?,
      ),
      _ => Future.value(
        jsonEncode({
          'ok': false,
          'code': 'tool_not_available',
          'error': 'No matching browser tool is available: $name',
        }),
      ),
    };
  }

  static Map<String, dynamic> get _browserOpenTool => {
    'type': 'function',
    'function': {
      'name': 'browser_open',
      'description':
          'Open a URL in the built-in browser pane. On wide layouts it opens to the right of the workspace; on narrow layouts it opens above the chat input. Use this first, then browser_snapshot to inspect the page. Returns the final URL and title.',
      'parameters': {
        'type': 'object',
        'properties': {
          'url': {
            'type': 'string',
            'description':
                'The URL to navigate to. https:// is assumed if no scheme is given.',
          },
          'reason': {
            'type': 'string',
            'description': 'Short note on why you are opening this page.',
          },
        },
        'required': ['url'],
      },
    },
  };

  static Map<String, dynamic> get _browserSnapshotTool => {
    'type': 'function',
    'function': {
      'name': 'browser_snapshot',
      'description':
          'List the visible interactive elements (links, buttons, inputs, selects) of the current page, each with a stable "ref" index plus tag, label, name and type. Pass a ref to browser_fill / browser_click. Re-run after navigation.',
      'parameters': {
        'type': 'object',
        'properties': {
          'max_elements': {
            'type': 'integer',
            'description': 'Maximum number of elements to return (default 80).',
          },
        },
      },
    },
  };

  static Map<String, dynamic> get _browserGetContentTool => {
    'type': 'function',
    'function': {
      'name': 'browser_get_content',
      'description':
          'Read the current page for parsing/scraping. format "text" returns rendered innerText; "html" returns full HTML. Large content is truncated.',
      'parameters': {
        'type': 'object',
        'properties': {
          'format': {
            'type': 'string',
            'enum': ['text', 'html'],
            'description':
                'text (default) for readable text, html for raw markup.',
          },
          'max_chars': {
            'type': 'integer',
            'description': 'Maximum characters to return (default 100000).',
          },
        },
      },
    },
  };

  static Map<String, dynamic> get _browserScreenshotTool => {
    'type': 'function',
    'function': {
      'name': 'browser_screenshot',
      'description':
          'Capture a PNG screenshot of the current page. Returns base64 image data.',
      'parameters': {'type': 'object', 'properties': <String, dynamic>{}},
    },
  };

  static Map<String, dynamic> get _browserWaitTool => {
    'type': 'function',
    'function': {
      'name': 'browser_wait',
      'description':
          'Wait for the page to finish loading, or until a CSS selector appears. Use after a click that triggers navigation or async content.',
      'parameters': {
        'type': 'object',
        'properties': {
          'selector': {
            'type': 'string',
            'description':
                'Optional CSS selector to wait for. Omit to just wait for load.',
          },
          'timeout_ms': {
            'type': 'integer',
            'description':
                'Maximum time to wait in milliseconds (default 8000).',
          },
        },
      },
    },
  };

  static Map<String, dynamic> get _browserNavigateHistoryTool => {
    'type': 'function',
    'function': {
      'name': 'browser_navigate_history',
      'description': 'Navigate the browser history: back, forward, or reload.',
      'parameters': {
        'type': 'object',
        'properties': {
          'direction': {
            'type': 'string',
            'enum': ['back', 'forward', 'reload'],
            'description': 'Which history navigation to perform.',
          },
        },
        'required': ['direction'],
      },
    },
  };

  static Map<String, dynamic> get _browserCloseTool => {
    'type': 'function',
    'function': {
      'name': 'browser_close',
      'description': 'Close the built-in browser pane.',
      'parameters': {'type': 'object', 'properties': <String, dynamic>{}},
    },
  };

  static Map<String, dynamic> get _browserFillTool => {
    'type': 'function',
    'function': {
      'name': 'browser_fill',
      'description':
          'Type a value into a form field, identified by "ref" (from browser_snapshot) or a CSS "selector". Requires user approval. Password values are redacted in the approval prompt.',
      'parameters': {
        'type': 'object',
        'properties': {
          'ref': {
            'type': 'integer',
            'description': 'Element ref from browser_snapshot.',
          },
          'selector': {
            'type': 'string',
            'description': 'CSS selector (alternative to ref).',
          },
          'value': {'type': 'string', 'description': 'The text to enter.'},
          'reason': {
            'type': 'string',
            'description': 'Why this field is being filled.',
          },
        },
        'required': ['value'],
      },
    },
  };

  static Map<String, dynamic> get _browserClickTool => {
    'type': 'function',
    'function': {
      'name': 'browser_click',
      'description':
          'Click an element identified by "ref" (from browser_snapshot) or a CSS "selector". May navigate or change page state. Requires user approval. Use only refs from the latest browser_snapshot; if you need to submit a form after filling a field, prefer browser_submit instead of guessing a submit button ref.',
      'parameters': {
        'type': 'object',
        'properties': {
          'ref': {
            'type': 'integer',
            'description': 'Element ref from browser_snapshot.',
          },
          'selector': {
            'type': 'string',
            'description': 'CSS selector (alternative to ref).',
          },
          'reason': {
            'type': 'string',
            'description': 'Why this element is being clicked.',
          },
        },
      },
    },
  };

  static Map<String, dynamic> get _browserSubmitTool => {
    'type': 'function',
    'function': {
      'name': 'browser_submit',
      'description':
          'Submit a form. Optionally provide a CSS "selector" for a field/button inside the target form; otherwise the first form is submitted. Requires user approval. Prefer this after browser_fill for searches and forms instead of guessing a submit button ref.',
      'parameters': {
        'type': 'object',
        'properties': {
          'selector': {
            'type': 'string',
            'description': 'Optional CSS selector inside the target form.',
          },
          'reason': {
            'type': 'string',
            'description': 'Why the form is being submitted.',
          },
        },
      },
    },
  };

  static Map<String, dynamic> get _browserEvalTool => {
    'type': 'function',
    'function': {
      'name': 'browser_eval',
      'description':
          'Run JavaScript in the current page and return its result (the body should "return" a JSON-serializable value). Use for advanced scraping when snapshot/content are insufficient. Requires user approval.',
      'parameters': {
        'type': 'object',
        'properties': {
          'script': {
            'type': 'string',
            'description':
                'JavaScript body; use "return <value>" to return data.',
          },
          'reason': {
            'type': 'string',
            'description': 'Why this script needs to run.',
          },
        },
        'required': ['script'],
      },
    },
  };

  static Map<String, dynamic> get _browserSaveDataTool => {
    'type': 'function',
    'function': {
      'name': 'browser_save_data',
      'description':
          'Save extracted data to a file. Defaults to Caverno application storage; set destination to downloads or documents only when the user explicitly requested that location. Requires user approval.',
      'parameters': {
        'type': 'object',
        'properties': {
          'filename': {
            'type': 'string',
            'description': 'File name, e.g. "usage.json".',
          },
          'data': {
            'type': 'string',
            'description': 'The file content (typically a JSON string).',
          },
          'format': {
            'type': 'string',
            'description': 'File extension to enforce (default "json").',
          },
          'destination': {
            'type': 'string',
            'enum': ['app', 'downloads', 'documents'],
            'description':
                'Optional save location. Use "app" by default. Use "downloads" or "documents" only when the user explicitly asks for that folder.',
          },
          'reason': {'type': 'string', 'description': 'What is being saved.'},
        },
        'required': ['filename', 'data'],
      },
    },
  };
}
