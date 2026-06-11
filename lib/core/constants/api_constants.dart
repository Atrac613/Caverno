class ApiConstants {
  ApiConstants._();

  static const String defaultBaseUrl = 'http://localhost:1234/v1';
  static const String defaultModel = 'mlx-community/GLM-4.7-Flash-4bit';
  static const String defaultApiKey = 'no-key';
  static const String appleFoundationModelsModelId = 'apple-foundation-models';
  static const String nvidiaNimBaseUrl = 'https://integrate.api.nvidia.com/v1';
  static const String nvidiaNimDefaultModel =
      'nvidia/llama-3.1-nemotron-ultra-253b-v1';
  static const List<String> nvidiaNimModelIds = [
    'nvidia/llama-3.1-nemotron-nano-8b-v1',
    'nvidia/llama-3.1-nemotron-ultra-253b-v1',
    'nvidia/llama-3.3-nemotron-super-49b-v1',
    'nvidia/llama-3.3-nemotron-super-49b-v1.5',
    'nvidia/nemotron-3-nano-30b-a3b',
    'nvidia/nemotron-3-super-120b-a12b',
    'nvidia/nemotron-3-ultra-550b-a55b',
    'nvidia/nvidia-nemotron-nano-9b-v2',
    'openai/gpt-oss-20b',
    'openai/gpt-oss-120b',
  ];

  static const double defaultTemperature = 0.7;
  static const int defaultMaxTokens = 4096;

  static bool isNvidiaNimCloudBaseUrl(String baseUrl) {
    final uri = Uri.tryParse(baseUrl.trim());
    if (uri == null) return false;
    final path = uri.path.endsWith('/') && uri.path.length > 1
        ? uri.path.substring(0, uri.path.length - 1)
        : uri.path;
    return uri.scheme == 'https' &&
        uri.host.toLowerCase() == 'integrate.api.nvidia.com' &&
        (path.isEmpty || path == '/v1');
  }
}
