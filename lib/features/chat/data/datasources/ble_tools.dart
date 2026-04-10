/// BLE tool definitions for the LLM in OpenAI function-call format.
class BleTools {
  BleTools._();

  static const Set<String> allToolNames = {
    'ble_start_scan',
    'ble_stop_scan',
    'ble_get_scan_results',
    'ble_connect',
    'ble_disconnect',
    'ble_discover_services',
    'ble_read_characteristic',
    'ble_write_characteristic',
    'ble_subscribe_characteristic',
    'ble_unsubscribe_characteristic',
    'ble_get_connection_state',
    'ble_start_advertising',
    'ble_stop_advertising',
    'ble_add_service',
    'ble_update_characteristic',
    'ble_get_peripheral_state',
  };

  // ---------------------------------------------------------------------------
  // Central tools
  // ---------------------------------------------------------------------------

  static Map<String, dynamic> get startScanTool => {
    'type': 'function',
    'function': {
      'name': 'ble_start_scan',
      'description':
          'Start scanning for nearby BLE (Bluetooth Low Energy) devices. '
          'Results are cached and can be retrieved with ble_get_scan_results. '
          'Scanning auto-stops after the timeout.',
      'parameters': {
        'type': 'object',
        'properties': {
          'timeout': {
            'type': 'integer',
            'description': 'Scan duration in seconds (default 10, max 60).',
          },
          'service_uuids': {
            'type': 'array',
            'items': {'type': 'string'},
            'description':
                'Optional list of service UUIDs to filter scan results.',
          },
        },
        'required': <String>[],
      },
    },
  };

  static Map<String, dynamic> get stopScanTool => {
    'type': 'function',
    'function': {
      'name': 'ble_stop_scan',
      'description': 'Stop an ongoing BLE scan.',
      'parameters': {'type': 'object', 'properties': {}},
    },
  };

  static Map<String, dynamic> get getScanResultsTool => {
    'type': 'function',
    'function': {
      'name': 'ble_get_scan_results',
      'description':
          'Get the list of BLE devices discovered during the most recent scan. '
          'Each entry includes device_id, name, rssi, and advertised service UUIDs. '
          'Use device_id from these results to connect.',
      'parameters': {
        'type': 'object',
        'properties': {
          'sort_by': {
            'type': 'string',
            'enum': ['rssi', 'name'],
            'description': 'Sort results by signal strength or name.',
          },
        },
        'required': <String>[],
      },
    },
  };

  static Map<String, dynamic> get connectTool => {
    'type': 'function',
    'function': {
      'name': 'ble_connect',
      'description':
          'Connect to a BLE device by its device_id (obtained from '
          'ble_get_scan_results). Requires user confirmation.',
      'parameters': {
        'type': 'object',
        'properties': {
          'device_id': {
            'type': 'string',
            'description': 'The device_id from scan results.',
          },
        },
        'required': ['device_id'],
      },
    },
  };

  static Map<String, dynamic> get disconnectTool => {
    'type': 'function',
    'function': {
      'name': 'ble_disconnect',
      'description': 'Disconnect from a connected BLE device.',
      'parameters': {
        'type': 'object',
        'properties': {
          'device_id': {
            'type': 'string',
            'description': 'The device_id of the connected device.',
          },
        },
        'required': ['device_id'],
      },
    },
  };

  static Map<String, dynamic> get discoverServicesTool => {
    'type': 'function',
    'function': {
      'name': 'ble_discover_services',
      'description':
          'Discover GATT services and characteristics on a connected BLE device. '
          'Must be called after ble_connect and before read/write operations.',
      'parameters': {
        'type': 'object',
        'properties': {
          'device_id': {
            'type': 'string',
            'description': 'The device_id of the connected device.',
          },
        },
        'required': ['device_id'],
      },
    },
  };

  static Map<String, dynamic> get readCharacteristicTool => {
    'type': 'function',
    'function': {
      'name': 'ble_read_characteristic',
      'description':
          'Read the value of a GATT characteristic on a connected BLE device. '
          'If subscribed to notifications, returns the latest cached value. '
          'Call ble_discover_services first to find available UUIDs.',
      'parameters': {
        'type': 'object',
        'properties': {
          'device_id': {
            'type': 'string',
            'description': 'The device_id of the connected device.',
          },
          'service_uuid': {
            'type': 'string',
            'description': 'UUID of the GATT service.',
          },
          'characteristic_uuid': {
            'type': 'string',
            'description': 'UUID of the GATT characteristic.',
          },
          'encoding': {
            'type': 'string',
            'enum': ['hex', 'utf8', 'base64'],
            'description':
                'Encoding for the returned value (default: hex).',
          },
        },
        'required': ['device_id', 'service_uuid', 'characteristic_uuid'],
      },
    },
  };

  static Map<String, dynamic> get writeCharacteristicTool => {
    'type': 'function',
    'function': {
      'name': 'ble_write_characteristic',
      'description':
          'Write a value to a GATT characteristic on a connected BLE device.',
      'parameters': {
        'type': 'object',
        'properties': {
          'device_id': {
            'type': 'string',
            'description': 'The device_id of the connected device.',
          },
          'service_uuid': {
            'type': 'string',
            'description': 'UUID of the GATT service.',
          },
          'characteristic_uuid': {
            'type': 'string',
            'description': 'UUID of the GATT characteristic.',
          },
          'value': {
            'type': 'string',
            'description':
                'The value to write, encoded according to the encoding parameter.',
          },
          'encoding': {
            'type': 'string',
            'enum': ['hex', 'utf8', 'base64'],
            'description': 'Encoding of the value (default: hex).',
          },
          'write_type': {
            'type': 'string',
            'enum': ['withResponse', 'withoutResponse'],
            'description':
                'Write type (default: withResponse).',
          },
        },
        'required': [
          'device_id',
          'service_uuid',
          'characteristic_uuid',
          'value',
        ],
      },
    },
  };

  static Map<String, dynamic> get subscribeCharacteristicTool => {
    'type': 'function',
    'function': {
      'name': 'ble_subscribe_characteristic',
      'description':
          'Subscribe to notifications from a GATT characteristic. '
          'Incoming values are buffered (last 10). Use ble_read_characteristic '
          'to get the latest cached value.',
      'parameters': {
        'type': 'object',
        'properties': {
          'device_id': {
            'type': 'string',
            'description': 'The device_id of the connected device.',
          },
          'service_uuid': {
            'type': 'string',
            'description': 'UUID of the GATT service.',
          },
          'characteristic_uuid': {
            'type': 'string',
            'description': 'UUID of the GATT characteristic.',
          },
        },
        'required': ['device_id', 'service_uuid', 'characteristic_uuid'],
      },
    },
  };

  static Map<String, dynamic> get unsubscribeCharacteristicTool => {
    'type': 'function',
    'function': {
      'name': 'ble_unsubscribe_characteristic',
      'description':
          'Unsubscribe from notifications on a GATT characteristic.',
      'parameters': {
        'type': 'object',
        'properties': {
          'device_id': {
            'type': 'string',
            'description': 'The device_id of the connected device.',
          },
          'service_uuid': {
            'type': 'string',
            'description': 'UUID of the GATT service.',
          },
          'characteristic_uuid': {
            'type': 'string',
            'description': 'UUID of the GATT characteristic.',
          },
        },
        'required': ['device_id', 'service_uuid', 'characteristic_uuid'],
      },
    },
  };

  static Map<String, dynamic> get getConnectionStateTool => {
    'type': 'function',
    'function': {
      'name': 'ble_get_connection_state',
      'description':
          'Check the connection state of a BLE device (connected or disconnected).',
      'parameters': {
        'type': 'object',
        'properties': {
          'device_id': {
            'type': 'string',
            'description': 'The device_id to check.',
          },
        },
        'required': ['device_id'],
      },
    },
  };

  // ---------------------------------------------------------------------------
  // Peripheral tools
  // ---------------------------------------------------------------------------

  static Map<String, dynamic> get startAdvertisingTool => {
    'type': 'function',
    'function': {
      'name': 'ble_start_advertising',
      'description':
          'Start advertising this device as a BLE peripheral. '
          'Other devices can discover and connect to it. '
          'Not supported on Linux.',
      'parameters': {
        'type': 'object',
        'properties': {
          'local_name': {
            'type': 'string',
            'description':
                'The local name to advertise. Not supported on Windows.',
          },
          'service_uuids': {
            'type': 'array',
            'items': {'type': 'string'},
            'description': 'Service UUIDs to include in the advertisement.',
          },
        },
        'required': <String>[],
      },
    },
  };

  static Map<String, dynamic> get stopAdvertisingTool => {
    'type': 'function',
    'function': {
      'name': 'ble_stop_advertising',
      'description': 'Stop BLE peripheral advertising.',
      'parameters': {'type': 'object', 'properties': {}},
    },
  };

  static Map<String, dynamic> get addServiceTool => {
    'type': 'function',
    'function': {
      'name': 'ble_add_service',
      'description':
          'Add a GATT service with characteristics to this device (peripheral mode). '
          'Call before ble_start_advertising so the service is discoverable.',
      'parameters': {
        'type': 'object',
        'properties': {
          'service_uuid': {
            'type': 'string',
            'description': 'UUID for the new GATT service.',
          },
          'characteristics': {
            'type': 'array',
            'description': 'List of characteristic definitions.',
            'items': {
              'type': 'object',
              'properties': {
                'uuid': {
                  'type': 'string',
                  'description': 'UUID for the characteristic.',
                },
                'properties': {
                  'type': 'array',
                  'items': {
                    'type': 'string',
                    'enum': [
                      'read',
                      'write',
                      'write_without_response',
                      'notify',
                      'indicate',
                    ],
                  },
                  'description': 'Characteristic properties.',
                },
                'value': {
                  'type': 'string',
                  'description':
                      'Optional initial value (hex-encoded by default).',
                },
                'encoding': {
                  'type': 'string',
                  'enum': ['hex', 'utf8', 'base64'],
                  'description': 'Encoding of the initial value.',
                },
              },
              'required': ['uuid', 'properties'],
            },
          },
        },
        'required': ['service_uuid', 'characteristics'],
      },
    },
  };

  static Map<String, dynamic> get updateCharacteristicTool => {
    'type': 'function',
    'function': {
      'name': 'ble_update_characteristic',
      'description':
          'Update the value of a hosted GATT characteristic and notify '
          'all subscribed centrals.',
      'parameters': {
        'type': 'object',
        'properties': {
          'service_uuid': {
            'type': 'string',
            'description': 'UUID of the GATT service.',
          },
          'characteristic_uuid': {
            'type': 'string',
            'description': 'UUID of the GATT characteristic.',
          },
          'value': {
            'type': 'string',
            'description': 'New value to set.',
          },
          'encoding': {
            'type': 'string',
            'enum': ['hex', 'utf8', 'base64'],
            'description': 'Encoding of the value (default: hex).',
          },
        },
        'required': ['service_uuid', 'characteristic_uuid', 'value'],
      },
    },
  };

  static Map<String, dynamic> get getPeripheralStateTool => {
    'type': 'function',
    'function': {
      'name': 'ble_get_peripheral_state',
      'description':
          'Get the current peripheral state including advertising status, '
          'hosted services, and connected centrals.',
      'parameters': {'type': 'object', 'properties': {}},
    },
  };

  /// All tool definitions for registration.
  static List<Map<String, dynamic>> get allTools => [
    startScanTool,
    stopScanTool,
    getScanResultsTool,
    connectTool,
    disconnectTool,
    discoverServicesTool,
    readCharacteristicTool,
    writeCharacteristicTool,
    subscribeCharacteristicTool,
    unsubscribeCharacteristicTool,
    getConnectionStateTool,
    startAdvertisingTool,
    stopAdvertisingTool,
    addServiceTool,
    updateCharacteristicTool,
    getPeripheralStateTool,
  ];
}
