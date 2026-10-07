import 'dart:convert';

/// Interprets weather response codes without changing generic tool evidence.
abstract final class HttpResponseInterpretation {
  static Map<String, dynamic>? _tryDecodeJsonMap(String value) {
    try {
      final decoded = jsonDecode(value);
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  static List<String> lines(Map<String, dynamic> decoded) {
    final body = decoded['body'];
    if (body is! String || body.trim().isEmpty) {
      return const [];
    }

    final payload = _tryDecodeJsonMap(body);
    if (payload == null) {
      return const [];
    }

    final url = (decoded['url'] as String?)?.toLowerCase() ?? '';
    if (!url.contains('open-meteo.com') &&
        !_looksLikeOpenMeteoWeatherPayload(payload)) {
      return const [];
    }

    final weatherCodeLines = _openMeteoWeatherCodeLines(payload);
    if (weatherCodeLines.isEmpty) {
      return const [];
    }

    return [
      ...weatherCodeLines,
      'Use these WMO labels for weather descriptions; drizzle codes are '
          '51, 53, and 55, while rain codes are 61, 63, and 65.',
    ];
  }

  static bool _looksLikeOpenMeteoWeatherPayload(Map<String, dynamic> payload) {
    final dailyUnits = payload['daily_units'];
    if (dailyUnits is Map) {
      final weatherCodeUnit =
          dailyUnits['weathercode'] ?? dailyUnits['weather_code'];
      if (weatherCodeUnit is String &&
          weatherCodeUnit.toLowerCase().contains('wmo')) {
        return true;
      }
    }
    final hourlyUnits = payload['hourly_units'];
    if (hourlyUnits is Map) {
      final weatherCodeUnit =
          hourlyUnits['weathercode'] ?? hourlyUnits['weather_code'];
      if (weatherCodeUnit is String &&
          weatherCodeUnit.toLowerCase().contains('wmo')) {
        return true;
      }
    }
    return false;
  }

  static List<String> _openMeteoWeatherCodeLines(Map<String, dynamic> payload) {
    final lines = <String>[];
    final daily = payload['daily'];
    if (daily is Map) {
      _addOpenMeteoSeriesWeatherCodeLines(
        lines,
        sectionName: 'daily',
        values: daily['weathercode'] ?? daily['weather_code'],
        times: daily['time'],
      );
    }

    final currentWeather = payload['current_weather'];
    if (currentWeather is Map) {
      _addOpenMeteoScalarWeatherCodeLine(
        lines,
        context: 'current_weather',
        value: currentWeather['weathercode'] ?? currentWeather['weather_code'],
      );
    }

    final current = payload['current'];
    if (current is Map) {
      _addOpenMeteoScalarWeatherCodeLine(
        lines,
        context: 'current',
        value: current['weathercode'] ?? current['weather_code'],
      );
    }

    return lines.take(8).toList(growable: false);
  }

  static void _addOpenMeteoSeriesWeatherCodeLines(
    List<String> lines, {
    required String sectionName,
    required Object? values,
    required Object? times,
  }) {
    if (values is List) {
      for (var index = 0; index < values.length; index += 1) {
        final time = times is List && index < times.length
            ? times[index]
            : null;
        final context = time is String && time.trim().isNotEmpty
            ? '$sectionName ${time.trim()}'
            : '$sectionName index $index';
        _addOpenMeteoScalarWeatherCodeLine(
          lines,
          context: context,
          value: values[index],
        );
      }
      return;
    }

    _addOpenMeteoScalarWeatherCodeLine(
      lines,
      context: sectionName,
      value: values,
    );
  }

  static void _addOpenMeteoScalarWeatherCodeLine(
    List<String> lines, {
    required String context,
    required Object? value,
  }) {
    final code = _asInt(value);
    if (code == null) {
      return;
    }
    final label = _openMeteoWmoWeatherCodeLabels[code];
    if (label == null) {
      lines.add(
        'Open-Meteo $context weather code $code is not in the built-in WMO '
        'mapping; do not invent a weather label.',
      );
      return;
    }
    lines.add('Open-Meteo $context weather code $code = $label.');
  }

  static int? _asInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value.trim());
    }
    return null;
  }

  static const Map<int, String> _openMeteoWmoWeatherCodeLabels = {
    0: 'Clear sky',
    1: 'Mainly clear',
    2: 'Partly cloudy',
    3: 'Overcast',
    45: 'Fog',
    48: 'Depositing rime fog',
    51: 'Drizzle: Light intensity',
    53: 'Drizzle: Moderate intensity',
    55: 'Drizzle: Dense intensity',
    56: 'Freezing drizzle: Light intensity',
    57: 'Freezing drizzle: Dense intensity',
    61: 'Rain: Slight intensity',
    63: 'Rain: Moderate intensity',
    65: 'Rain: Heavy intensity',
    66: 'Freezing rain: Light intensity',
    67: 'Freezing rain: Heavy intensity',
    71: 'Snow fall: Slight intensity',
    73: 'Snow fall: Moderate intensity',
    75: 'Snow fall: Heavy intensity',
    77: 'Snow grains',
    80: 'Rain showers: Slight',
    81: 'Rain showers: Moderate',
    82: 'Rain showers: Violent',
    85: 'Snow showers: Slight',
    86: 'Snow showers: Heavy',
    95: 'Thunderstorm: Slight or moderate',
    96: 'Thunderstorm with slight hail',
    99: 'Thunderstorm with heavy hail',
  };
}
