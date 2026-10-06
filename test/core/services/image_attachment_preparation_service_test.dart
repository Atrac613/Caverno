import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:caverno/core/services/image_attachment_preparation_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('resizes the model payload to the shared 1024px boundary', () async {
    final original = await _makePng(width: 2048, height: 512);

    final prepared = await ImageAttachmentPreparationService.prepareForModel(
      bytes: original,
      mimeType: 'image/png',
      filePath: 'photo.png',
    );
    final codec = await ui.instantiateImageCodec(prepared.bytes);
    final frame = await codec.getNextFrame();

    expect(frame.image.width, 1024);
    expect(frame.image.height, 256);
    expect(prepared.mimeType, 'image/png');
    expect(prepared.bytes, isNot(equals(original)));

    frame.image.dispose();
    codec.dispose();
  });

  test('keeps a supported small image payload unchanged', () async {
    final original = await _makePng(width: 2, height: 1);

    final prepared = await ImageAttachmentPreparationService.prepareForModel(
      bytes: original,
      mimeType: 'image/png',
      filePath: 'photo.png',
    );

    expect(prepared.bytes, same(original));
    expect(prepared.mimeType, 'image/png');
  });
}

Future<Uint8List> _makePng({required int width, required int height}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawColor(const ui.Color(0xff336699), ui.BlendMode.srcOver);
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  return data!.buffer.asUint8List();
}
