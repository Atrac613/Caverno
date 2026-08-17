import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/datasources/skill_catalog_data_source.dart';
import '../../domain/entities/skill_catalog_entry.dart';

final skillCatalogDataSourceProvider = Provider<SkillCatalogDataSource>(
  (ref) => const SkillCatalogDataSource(),
);

/// Prebuilt skills bundled with the app, loaded from the asset bundle once.
final skillCatalogProvider = FutureProvider<List<SkillCatalogEntry>>(
  (ref) => ref.watch(skillCatalogDataSourceProvider).load(),
);
