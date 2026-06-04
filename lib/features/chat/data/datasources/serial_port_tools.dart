/// Serial port tool definitions for the LLM in OpenAI function-call format.
///
/// Desktop only (macOS / Windows / Linux). Typical workflow:
/// `serial_list_ports` → `serial_open` (requires user confirmation) →
/// `serial_read` / `serial_write` → `serial_close`.
class SerialPortTools {
  SerialPortTools._();

  static const Set<String> allToolNames = {
    'serial_list_ports',
    'serial_open',
    'serial_read',
    'serial_decode',
    'serial_write',
    'serial_close',
  };

  static Map<String, dynamic> get listPortsTool => {
    'type': 'function',
    'function': {
      'name': 'serial_list_ports',
      'description':
          'List the serial ports available on this computer (e.g. USB-serial '
          'adapters, microcontrollers). Each entry includes name, description, '
          'manufacturer, vendor_id/product_id, transport, and whether it is '
          'already open. Use a port name from here with serial_open.',
      'parameters': {'type': 'object', 'properties': {}},
    },
  };

  static Map<String, dynamic> get openTool => {
    'type': 'function',
    'function': {
      'name': 'serial_open',
      'description':
          'Open a serial port for reading and writing and start buffering '
          'incoming data. Requires user confirmation (the user is shown the '
          'port and baud rate, and that read & write access is granted). '
          'Opening a port may reset some devices (DTR toggle). After opening, '
          'use serial_read to retrieve buffered data and serial_write to send '
          'data. Always serial_close when finished.',
      'parameters': {
        'type': 'object',
        'properties': {
          'port': {
            'type': 'string',
            'description':
                'The port name from serial_list_ports (e.g. '
                '"/dev/cu.usbserial-1420", "COM3").',
          },
          'baud_rate': {
            'type': 'integer',
            'description': 'Baud rate (default 9600). Common: 9600, 115200.',
          },
          'data_bits': {
            'type': 'integer',
            'description': 'Data bits: 5, 6, 7, or 8 (default 8).',
          },
          'parity': {
            'type': 'string',
            'enum': ['none', 'odd', 'even', 'mark', 'space'],
            'description': 'Parity (default none).',
          },
          'stop_bits': {
            'type': 'integer',
            'description': 'Stop bits: 1 or 2 (default 1).',
          },
          'flow_control': {
            'type': 'string',
            'enum': ['none', 'rtscts', 'xonxoff', 'dtrdsr'],
            'description': 'Flow control (default none).',
          },
        },
        'required': ['port'],
      },
    },
  };

  static Map<String, dynamic> get readTool => {
    'type': 'function',
    'function': {
      'name': 'serial_read',
      'description':
          'Read the data buffered from an open serial port since the last '
          'read. Returns the decoded data plus bytes_read, bytes_remaining and '
          'a content_hint (likely_type text/binary/mixed). Call repeatedly to '
          'monitor a continuous stream. For binary data prefer encoding '
          '"hexdump" (offset + hex + ASCII, best for analysis) or "hex". For '
          'frame-based protocols set frame_delimiter or frame_length to get an '
          'array of complete frames (any trailing partial frame is kept for the '
          'next read). To parse numeric fields exactly, follow up with '
          'serial_decode. The port must have been opened with serial_open.',
      'parameters': {
        'type': 'object',
        'properties': {
          'port': {
            'type': 'string',
            'description': 'The name of an open serial port.',
          },
          'encoding': {
            'type': 'string',
            'enum': ['utf8', 'hex', 'hexdump', 'base64'],
            'description':
                'How to decode the bytes (default utf8). Use "hexdump" or '
                '"hex" for binary protocols.',
          },
          'max_bytes': {
            'type': 'integer',
            'description':
                'Maximum number of buffered bytes to return (default: all). '
                'Ignored when framing.',
          },
          'clear': {
            'type': 'boolean',
            'description':
                'Whether to remove the returned bytes from the buffer '
                '(default true). Ignored when framing — complete frames are '
                'always consumed and the partial remainder is retained.',
          },
          'frame_delimiter': {
            'type': 'string',
            'description':
                'Hex of a terminator that ends each frame (e.g. "0a" for LF, '
                '"0d0a" for CRLF). Splits the buffer into complete frames.',
          },
          'frame_length': {
            'type': 'integer',
            'description':
                'Fixed frame size in bytes. Splits the buffer into '
                'fixed-length frames. Ignored if frame_delimiter is set.',
          },
          'max_frames': {
            'type': 'integer',
            'description': 'Maximum frames to return per call (default 200).',
          },
          'include_stats': {
            'type': 'boolean',
            'description':
                'Include byte-distribution stats (distinct bytes, null count, '
                'entropy, top bytes) to help identify structure (default '
                'false).',
          },
        },
        'required': ['port'],
      },
    },
  };

  static Map<String, dynamic> get decodeTool => {
    'type': 'function',
    'function': {
      'name': 'serial_decode',
      'description':
          'Deterministically parse a byte sequence into named numeric/string '
          'fields using a Python-struct-style format. Use this instead of '
          'computing values from a hex dump yourself — it removes arithmetic '
          'errors. Provide the bytes via "data" (hex, e.g. from serial_read) '
          'or read them from an open "port" buffer.',
      'parameters': {
        'type': 'object',
        'properties': {
          'data': {
            'type': 'string',
            'description':
                'Hex bytes to decode (e.g. "01 2c 00 00 80 3f"). Preferred '
                'input; takes precedence over port.',
          },
          'port': {
            'type': 'string',
            'description':
                'Alternatively, an open serial port to decode from its '
                'buffered bytes.',
          },
          'format': {
            'type': 'string',
            'description':
                'Struct format. Byte order: "<" little-endian (default), ">" '
                'or "!" big-endian. Types: b/B int8/uint8, h/H int16/uint16, '
                'i/I (or l/L) int32/uint32, q/Q int64/uint64, f float32, d '
                'float64, "Nx" skip N pad bytes, "Ns" an N-byte string. A '
                'leading count repeats a type, e.g. "<2Hf" or ">Ifq".',
          },
          'fields': {
            'type': 'array',
            'items': {'type': 'string'},
            'description':
                'Optional names for the decoded values, in order, returned as '
                'a fields object.',
          },
          'consume': {
            'type': 'boolean',
            'description':
                'When reading from a port, remove the parsed bytes from the '
                'buffer (default false). Ignored when data is provided.',
          },
        },
        'required': ['format'],
      },
    },
  };

  static Map<String, dynamic> get writeTool => {
    'type': 'function',
    'function': {
      'name': 'serial_write',
      'description':
          'Send data to an open serial port (e.g. an AT command or a binary '
          'frame). For utf8, include control characters directly (e.g. a '
          'trailing carriage return / line feed). The port must have been '
          'opened with serial_open.',
      'parameters': {
        'type': 'object',
        'properties': {
          'port': {
            'type': 'string',
            'description': 'The name of an open serial port.',
          },
          'data': {
            'type': 'string',
            'description':
                'The data to send, encoded according to the encoding '
                'parameter.',
          },
          'encoding': {
            'type': 'string',
            'enum': ['utf8', 'hex', 'base64'],
            'description': 'How to interpret data (default utf8).',
          },
        },
        'required': ['port', 'data'],
      },
    },
  };

  static Map<String, dynamic> get closeTool => {
    'type': 'function',
    'function': {
      'name': 'serial_close',
      'description':
          'Close an open serial port and stop buffering its data. Always call '
          'this when finished to release the device.',
      'parameters': {
        'type': 'object',
        'properties': {
          'port': {
            'type': 'string',
            'description': 'The name of the open serial port to close.',
          },
        },
        'required': ['port'],
      },
    },
  };

  /// All tool definitions for registration.
  static List<Map<String, dynamic>> get allTools => [
    listPortsTool,
    openTool,
    readTool,
    decodeTool,
    writeTool,
    closeTool,
  ];
}
