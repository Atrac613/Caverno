import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/entities/video_attachment_draft.dart';
import 'package:caverno/features/chat/presentation/widgets/composer_video_picker.dart';

VideoAttachmentDraft _draft({int? sizeBytes, int? durationMs}) =>
    VideoAttachmentDraft(
      path: '/tmp/clip.mp4',
      mimeType: 'video/mp4',
      displayName: 'clip.mp4',
      sizeBytes: sizeBytes,
      durationMs: durationMs,
    );

void main() {
  const picker = ComposerVideoPicker();

  group('mimeTypeFor', () {
    test('maps the containers a picker can hand back', () {
      expect(ComposerVideoPicker.mimeTypeFor('/a/b.MOV'), 'video/quicktime');
      expect(ComposerVideoPicker.mimeTypeFor('/a/b.webm'), 'video/webm');
      expect(ComposerVideoPicker.mimeTypeFor('/a/b.mkv'), 'video/x-matroska');
      expect(ComposerVideoPicker.mimeTypeFor('/a/b.avi'), 'video/x-msvideo');
    });

    test('falls back to mp4 for anything else', () {
      expect(ComposerVideoPicker.mimeTypeFor('/a/b.mp4'), 'video/mp4');
      expect(ComposerVideoPicker.mimeTypeFor('/a/b'), 'video/mp4');
    });
  });

  group('validate', () {
    test('accepts a clip inside the limits with nothing to say', () {
      final choice = picker.validate(
        _draft(sizeBytes: 1024, durationMs: 4000),
      );

      expect(choice.video, isNotNull);
      expect(choice.noticeKey, isNull);
    });

    test('refuses an oversized clip and says why', () {
      final choice = picker.validate(
        _draft(sizeBytes: VideoAttachmentDraft.maxFileBytes + 1),
      );

      expect(choice.video, isNull);
      expect(choice.noticeKey, 'message.video_too_large');
      expect(choice.noticeArgs, containsPair('limit', '10.0 MB'));
    });

    test('accepts a long clip but warns about the context it will cost', () {
      final choice = picker.validate(
        _draft(
          sizeBytes: 1024,
          durationMs: VideoAttachmentDraft.warnAboveDurationMs + 1,
        ),
      );

      expect(choice.video, isNotNull);
      expect(choice.noticeKey, 'message.video_long_warning');
    });

    test('a cancelled pick is not an error', () {
      expect(picker.validate(null).video, isNull);
      expect(picker.validate(null).noticeKey, isNull);
    });
  });

  group('chipLabel', () {
    test('joins what is known and skips what is not', () {
      expect(_draft(sizeBytes: 2048).chipLabel, 'clip.mp4 · 2.0 KB');
      expect(_draft().chipLabel, 'clip.mp4');
      expect(
        _draft(sizeBytes: 2048, durationMs: 90000).chipLabel,
        'clip.mp4 · 2.0 KB · 1:30',
      );
    });
  });
}
