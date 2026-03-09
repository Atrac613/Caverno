import 'package:openai_dart/openai_dart.dart';

import '../../../core/constants/api_constants.dart';

class ModelRemoteDataSource {
  ModelRemoteDataSource({String? baseUrl, String? apiKey})
    : _client = OpenAIClient(
        baseUrl: baseUrl ?? ApiConstants.defaultBaseUrl,
        apiKey: apiKey ?? ApiConstants.defaultApiKey,
      );

  final OpenAIClient _client;

  Future<List<String>> listModelIds() async {
    final response = await _client.listModels();
    final ids = response.data.map((model) => model.id).toSet().toList()..sort();

    if (ids.isEmpty) {
      throw Exception('利用可能なモデルが取得できませんでした');
    }

    return ids;
  }
}
