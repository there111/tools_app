import 'dart:typed_data';
import 'package:pdfx/pdfx.dart';

class PdfService {
  /// 打开文档：优先用文件路径（原生性能好），无路径时用字节数据（网页）
  static Future<PdfDocument> _open({String? filePath, Uint8List? data}) async {
    if (filePath != null) {
      return PdfDocument.openFile(filePath);
    }
    if (data != null) {
      return PdfDocument.openData(data);
    }
    throw ArgumentError('filePath or data required');
  }

  static Future<int> getPageCount({String? filePath, Uint8List? data}) async {
    final doc = await _open(filePath: filePath, data: data);
    try {
      return doc.pagesCount;
    } finally {
      await doc.close();
    }
  }

  /// 渲染单页，返回 PNG 字节
  static Future<Uint8List> renderPage(int pageIndex, {String? filePath, Uint8List? data, double scale = 2.0}) async {
    final doc = await _open(filePath: filePath, data: data);
    try {
      final page = await doc.getPage(pageIndex + 1);
      try {
        final w = (page.width * scale).roundToDouble();
        final h = (page.height * scale).roundToDouble();
        final pageImage = await page.render(
          width: w, height: h, format: PdfPageImageFormat.png,
        );
        if (pageImage == null) throw Exception('渲染失败');
        return pageImage.bytes;
      } finally {
        await page.close();
      }
    } finally {
      await doc.close();
    }
  }

  /// 一次打开，批量渲染所有页，返回 PNG 列表
  static Future<List<Uint8List>> renderAllPages({
    String? filePath,
    Uint8List? data,
    double scale = 2.0,
    void Function(int current, int total)? onProgress,
  }) async {
    final doc = await _open(filePath: filePath, data: data);
    try {
      final results = <Uint8List>[];
      for (int i = 1; i <= doc.pagesCount; i++) {
        final page = await doc.getPage(i);
        try {
          final w = (page.width * scale).roundToDouble();
          final h = (page.height * scale).roundToDouble();
          final pageImage = await page.render(
            width: w, height: h, format: PdfPageImageFormat.png,
          );
          if (pageImage == null) throw Exception('渲染第 $i 页失败');
          results.add(pageImage.bytes);
          onProgress?.call(i, doc.pagesCount);
        } finally {
          await page.close();
        }
      }
      return results;
    } finally {
      await doc.close();
    }
  }
}
