import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/media_host_service.dart';
import '../../data/datasources/video_attachment_delivery.dart';

/// The one media host for the app.
///
/// Shared rather than per-datasource so a single listener serves every
/// endpoint, and so it can shut itself down once no attachment is live.
final mediaHostServiceProvider = Provider<MediaHostService>((ref) {
  final service = MediaHostService();
  ref.onDispose(service.stop);
  return service;
});

/// Shared so the "this endpoint never fetched our URL" finding is remembered
/// across datasource rebuilds instead of being rediscovered every time.
final videoAttachmentDeliveryProvider = Provider<VideoAttachmentDelivery>((ref) {
  return VideoAttachmentDelivery(mediaHost: ref.watch(mediaHostServiceProvider));
});
