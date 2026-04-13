import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../utils/logger.dart';

final securityScopedBookmarkServiceProvider =
    Provider<SecurityScopedBookmarkService>((ref) {
      return SecurityScopedBookmarkService();
    });

class SecurityScopedBookmarkAccessResult {
  const SecurityScopedBookmarkAccessResult({
    required this.accessStarted,
    this.resolvedPath,
    this.refreshedBookmark,
    this.error,
  });

  const SecurityScopedBookmarkAccessResult.success({
    String? resolvedPath,
    String? refreshedBookmark,
  }) : this(
         accessStarted: true,
         resolvedPath: resolvedPath,
         refreshedBookmark: refreshedBookmark,
       );

  const SecurityScopedBookmarkAccessResult.failure(String error)
    : this(accessStarted: false, error: error);

  final bool accessStarted;
  final String? resolvedPath;
  final String? refreshedBookmark;
  final String? error;
}

class SecurityScopedBookmarkService {
  static const MethodChannel _channel = MethodChannel(
    'com.caverno/security_scoped_bookmarks',
  );

  Future<String?> createBookmark(String path) async {
    if (!Platform.isMacOS) return null;

    try {
      return await _channel.invokeMethod<String>('createBookmark', {
        'path': path,
      });
    } on MissingPluginException {
      return null;
    } on PlatformException catch (error) {
      appLog('[Bookmark] Failed to create bookmark for $path: $error');
      return null;
    }
  }

  Future<SecurityScopedBookmarkAccessResult> startAccessingBookmark(
    String bookmark,
  ) async {
    if (!Platform.isMacOS) {
      return const SecurityScopedBookmarkAccessResult.success();
    }

    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'startAccessingBookmark',
        {'bookmark': bookmark},
      );
      if (result == null) {
        return const SecurityScopedBookmarkAccessResult.failure(
          'Bookmark restore returned no result',
        );
      }

      return SecurityScopedBookmarkAccessResult(
        accessStarted: result['accessStarted'] == true,
        resolvedPath: result['path'] as String?,
        refreshedBookmark: result['bookmark'] as String?,
        error: result['error'] as String?,
      );
    } on MissingPluginException {
      return const SecurityScopedBookmarkAccessResult.success();
    } on PlatformException catch (error) {
      appLog('[Bookmark] Failed to start accessing bookmark: $error');
      return SecurityScopedBookmarkAccessResult.failure(
        error.message ?? '$error',
      );
    }
  }
}
