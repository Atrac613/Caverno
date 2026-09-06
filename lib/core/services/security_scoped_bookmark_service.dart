import 'dart:io';

import 'package:file_picker/file_picker.dart';
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

class DirectoryPickResult {
  const DirectoryPickResult.cancelled()
    : path = null,
      bookmark = null,
      error = null;

  const DirectoryPickResult.picked(this.path, {this.bookmark}) : error = null;

  const DirectoryPickResult.failed(this.error) : path = null, bookmark = null;

  final String? path;
  final String? bookmark;
  final String? error;

  bool get isCancelled => path == null && error == null;
}

class SecurityScopedBookmarkService {
  SecurityScopedBookmarkService({
    MethodChannel channel = _defaultChannel,
    bool? isMacOS,
    Future<String?> Function({String? initialDirectory})?
    fallbackDirectoryPicker,
  }) : _channel = channel,
       _isMacOS = isMacOS ?? Platform.isMacOS,
       _fallbackDirectoryPicker = fallbackDirectoryPicker;

  static const MethodChannel _defaultChannel = MethodChannel(
    'com.caverno/security_scoped_bookmarks',
  );

  final MethodChannel _channel;
  final bool _isMacOS;
  final Future<String?> Function({String? initialDirectory})?
  _fallbackDirectoryPicker;

  Future<String?> createBookmark(String path) async {
    if (!_isMacOS) return null;

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
    if (!_isMacOS) {
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

  /// Picks a project root directory.
  ///
  /// On macOS this uses the existing bookmark channel so NSOpenPanel can
  /// create folders. A cancel returns [DirectoryPickResult.cancelled]; a
  /// native failure returns [DirectoryPickResult.failed] instead of looking
  /// like a cancel. Other platforms keep [FilePicker.getDirectoryPath].
  Future<DirectoryPickResult> pickDirectory({String? initialDirectory}) async {
    if (_isMacOS) {
      try {
        final payload = await _channel.invokeMethod<dynamic>('pickDirectory', {
          if (initialDirectory != null && initialDirectory.isNotEmpty)
            'initialDirectory': initialDirectory,
        });
        return _resultFromPickerPayload(payload);
      } on MissingPluginException {
        return _pickWithFallback(initialDirectory);
      } on PlatformException catch (error) {
        appLog('[Bookmark] Failed to pick directory: $error');
        return DirectoryPickResult.failed(error.message ?? '$error');
      }
    }

    return _pickWithFallback(initialDirectory);
  }

  DirectoryPickResult _resultFromPickerPayload(Object? payload) {
    if (payload == null) {
      return const DirectoryPickResult.cancelled();
    }
    if (payload is String) {
      if (payload.isEmpty) {
        return const DirectoryPickResult.cancelled();
      }
      return DirectoryPickResult.picked(payload);
    }
    if (payload is Map) {
      final error = payload['error'] as String?;
      if (error != null && error.isNotEmpty) {
        return DirectoryPickResult.failed(error);
      }
      final path = payload['path'] as String?;
      if (path == null || path.isEmpty) {
        return const DirectoryPickResult.cancelled();
      }
      final bookmarkError = payload['bookmarkError'] as String?;
      if (bookmarkError != null && bookmarkError.isNotEmpty) {
        appLog('[Bookmark] Panel bookmark failed: $bookmarkError');
      }
      final bookmark = payload['bookmark'] as String?;
      return DirectoryPickResult.picked(
        path,
        bookmark: bookmark == null || bookmark.isEmpty ? null : bookmark,
      );
    }
    return const DirectoryPickResult.failed(
      'Directory picker returned an unexpected result',
    );
  }

  Future<DirectoryPickResult> _pickWithFallback(
    String? initialDirectory,
  ) async {
    final fallback = _fallbackDirectoryPicker;
    final path = fallback == null
        ? await FilePicker.getDirectoryPath(initialDirectory: initialDirectory)
        : await fallback(initialDirectory: initialDirectory);
    if (path == null || path.isEmpty) {
      return const DirectoryPickResult.cancelled();
    }
    return DirectoryPickResult.picked(path);
  }
}
