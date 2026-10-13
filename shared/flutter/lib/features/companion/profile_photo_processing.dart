import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'models.dart';

/// Source limits are separate from the smaller, normalized DB photo limits.
class ProfilePhotoProcessing {
  static const maxSourceBytes = 8 * 1024 * 1024;
  static const maxSourceDimension = 8192;
  static const maxSourcePixels = 24 * 1024 * 1024;
  static const previewDimension = 1024;

  static Future<ui.Image> decode(Uint8List bytes) async {
    if (bytes.isEmpty || bytes.length > maxSourceBytes) {
      throw const FeatureFailure('8MB 이하의 사진을 선택해 주세요.');
    }
    final png =
        bytes.length >= 8 &&
        bytes[0] == 137 &&
        bytes[1] == 80 &&
        bytes[2] == 78 &&
        bytes[3] == 71;
    final jpeg =
        bytes.length >= 3 &&
        bytes[0] == 255 &&
        bytes[1] == 216 &&
        bytes[2] == 255;
    final webp =
        bytes.length >= 12 &&
        bytes[0] == 82 &&
        bytes[1] == 73 &&
        bytes[2] == 70 &&
        bytes[3] == 70 &&
        bytes[8] == 87 &&
        bytes[9] == 69 &&
        bytes[10] == 66 &&
        bytes[11] == 80;
    if (!png && !jpeg && !webp) {
      throw const FeatureFailure('JPG, PNG, WebP 사진을 선택해 주세요.');
    }
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    try {
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      if (descriptor.width > maxSourceDimension ||
          descriptor.height > maxSourceDimension ||
          descriptor.width * descriptor.height > maxSourcePixels) {
        throw const FeatureFailure('사진 해상도가 너무 커요. 작은 사진을 선택해 주세요.');
      }
      final scale = math.min(
        1.0,
        previewDimension / math.max(descriptor.width, descriptor.height),
      );
      codec = await descriptor.instantiateCodec(
        targetWidth: math.max(1, (descriptor.width * scale).round()),
        targetHeight: math.max(1, (descriptor.height * scale).round()),
      );
      if (codec.frameCount != 1) {
        throw const FeatureFailure('움직이지 않는 사진을 선택해 주세요.');
      }
      return (await codec.getNextFrame()).image;
    } on FeatureFailure {
      rethrow;
    } catch (_) {
      throw const FeatureFailure('사진을 읽을 수 없어요. 다른 사진을 선택해 주세요.');
    } finally {
      codec?.dispose();
      descriptor?.dispose();
      buffer.dispose();
    }
  }

  static ui.Rect cropRect(
    ui.Image image, {
    double zoom = 1,
    double x = .5,
    double y = .5,
  }) {
    final side = math.min(image.width, image.height) / zoom.clamp(1, 4);
    return ui.Rect.fromLTWH(
      (image.width - side) * x.clamp(0, 1),
      (image.height - side) * y.clamp(0, 1),
      side,
      side,
    );
  }

  static void paint(
    ui.Canvas canvas,
    ui.Size size,
    ui.Image image, {
    double zoom = 1,
    double x = .5,
    double y = .5,
    int quarterTurns = 0,
  }) {
    final side = math.min(size.width, size.height);
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate((quarterTurns % 4) * math.pi / 2);
    canvas.drawImageRect(
      image,
      cropRect(image, zoom: zoom, x: x, y: y),
      ui.Rect.fromLTWH(-side / 2, -side / 2, side, side),
      ui.Paint()..filterQuality = ui.FilterQuality.high,
    );
    canvas.restore();
  }

  static Future<ProfilePhoto> encode(
    ui.Image image, {
    double zoom = 1,
    double x = .5,
    double y = .5,
    int quarterTurns = 0,
  }) async {
    // Reduce dimensions for detailed photos rather than exceed the DB byte cap.
    for (final dimension in [256, 192, 128, 96]) {
      final recorder = ui.PictureRecorder();
      paint(
        ui.Canvas(recorder),
        ui.Size.square(dimension.toDouble()),
        image,
        zoom: zoom,
        x: x,
        y: y,
        quarterTurns: quarterTurns,
      );
      final picture = recorder.endRecording();
      ui.Image? output;
      try {
        output = await picture.toImage(dimension, dimension);
        final encoded = await output.toByteData(format: ui.ImageByteFormat.png);
        if (encoded != null && encoded.lengthInBytes <= ProfilePhoto.maxBytes) {
          return ProfilePhoto.fromPng(
            encoded.buffer.asUint8List(
              encoded.offsetInBytes,
              encoded.lengthInBytes,
            ),
          );
        }
      } finally {
        output?.dispose();
        picture.dispose();
      }
    }
    throw const FeatureFailure('사진을 저장 크기로 줄이지 못했어요. 다른 사진을 선택해 주세요.');
  }
}
