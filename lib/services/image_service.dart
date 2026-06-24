import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

class ImageToolResult {
  final Uint8List bytes;
  final String filename;
  final int originalSize;
  final int newSize;

  ImageToolResult({
    required this.bytes,
    required this.filename,
    required this.originalSize,
    required this.newSize,
  });

  double get ratio => newSize / originalSize;
}

class ImageToolService {
  static ImageToolResult compress(
    Uint8List bytes,
    String filename, {
    int quality = 85,
  }) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) throw Exception('无法解码图片: $filename');

    final ext = p.extension(filename).toLowerCase();
    final output = _encode(decoded, ext, quality: quality);
    return ImageToolResult(
      bytes: output,
      filename: filename,
      originalSize: bytes.length,
      newSize: output.length,
    );
  }

  static ImageToolResult resize(
    Uint8List bytes,
    String filename, {
    int? width,
    int? height,
  }) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) throw Exception('无法解码图片: $filename');

    int targetW = width ?? decoded.width;
    int targetH = height ?? decoded.height;
    if (width != null && height == null) {
      targetH = (decoded.height * width / decoded.width).round();
    } else if (height != null && width == null) {
      targetW = (decoded.width * height / decoded.height).round();
    }

    final resized = img.copyResize(decoded, width: targetW, height: targetH);
    final ext = p.extension(filename).toLowerCase();
    final output = _encode(resized, ext);
    return ImageToolResult(
      bytes: output,
      filename: filename,
      originalSize: bytes.length,
      newSize: output.length,
    );
  }

  static ImageToolResult changeBackground(
    Uint8List bytes,
    String filename, {
    required int r,
    required int g,
    required int b,
    int tolerance = 40,
  }) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) throw Exception('无法解码图片: $filename');

    for (final pixel in decoded) {
      if (_isNearWhite(pixel, tolerance)) {
        pixel.r = r;
        pixel.g = g;
        pixel.b = b;
      }
    }
    final ext = p.extension(filename).toLowerCase();
    final output = _encode(decoded, ext);
    return ImageToolResult(
      bytes: output,
      filename: filename,
      originalSize: bytes.length,
      newSize: output.length,
    );
  }

  static ImageToolResult convertFormat(
    Uint8List bytes,
    String filename,
    String targetExt, {
    int quality = 90,
  }) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) throw Exception('无法解码图片: $filename');

    final newName = p.basenameWithoutExtension(filename) + targetExt;
    final output = _encode(decoded, targetExt, quality: quality);
    return ImageToolResult(
      bytes: output,
      filename: newName,
      originalSize: bytes.length,
      newSize: output.length,
    );
  }

  static Uint8List _encode(img.Image image, String ext, {int quality = 90}) {
    switch (ext) {
      case '.png':
        return Uint8List.fromList(img.encodePng(image));
      case '.webp':
        return Uint8List.fromList(img.encodePng(image));
      default: // .jpg, .jpeg
        return Uint8List.fromList(img.encodeJpg(image, quality: quality));
    }
  }

  static bool _isNearWhite(img.Pixel pixel, int tolerance) {
    return (pixel.r * 255).round() > (255 - tolerance) &&
        (pixel.g * 255).round() > (255 - tolerance) &&
        (pixel.b * 255).round() > (255 - tolerance);
  }
}
