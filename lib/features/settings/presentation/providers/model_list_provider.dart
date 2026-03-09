import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/model_remote_datasource.dart';

final modelListProvider = FutureProvider.autoDispose
    .family<List<String>, ({String baseUrl, String apiKey})>((
      ref,
      config,
    ) async {
      final dataSource = ModelRemoteDataSource(
        baseUrl: config.baseUrl,
        apiKey: config.apiKey,
      );
      return dataSource.listModelIds();
    });
