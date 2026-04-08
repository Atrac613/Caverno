import 'package:openai_dart/openai_dart.dart';

import '../../../core/constants/api_constants.dart';

class ModelRemoteDataSource {
  ModelRemoteDataSource({String? baseUrl, String? apiKey})
    : _client = OpenAIClient.withApiKey(
        apiKey ?? ApiConstants.defaultApiKey,
        baseUrl: baseUrl ?? ApiConstants.defaultBaseUrl,
      );

  final OpenAIClient _client;

  Future<List<String>> listModelIds() async {
    final response = await _client.models.list();
    final ids = response.data.map((model) => model.id).toSet().toList()..sort();

    if (ids.isEmpty) {
      throw Exception('No available models could be retrieved');
    }

    return ids;
  }
}
