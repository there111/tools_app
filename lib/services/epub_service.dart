import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';

class EpubService {
  /// 章节正则（复用阅读器的规则）
  static final _chapterPatterns = [
    RegExp(r'^[第序终番][\d一二三四五六七八九十百千]+[章节回话卷篇部]'),
    RegExp(r'^第[\d]+[章节回话卷篇部]'),
    RegExp(r'^[（(][\d一二三四五六七八九十百千]+[）)]'),
    RegExp(r'^\d+[、.]\s*'),
    RegExp(r'^第[\d一二三四五六七八九十百千]+\s+'),
    RegExp(r'^【[^】]+】\s*$'),
  ];

  /// TXT → EPUB 转换
  static Future<Uint8List> txtToEpub(
    String txtContent,
    String title, {
    String author = '',
  }) async {
    final lines = const LineSplitter().convert(txtContent);
    final chapters = _splitChapters(lines);

    final encoder = ZipEncoder();
    final archive = Archive();

    // mimetype (第一个文件，不压缩)
    archive.addFile(ArchiveFile('mimetype', 20, utf8.encode('application/epub+zip')));

    // META-INF/container.xml
    const containerXml = '''<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>''';
    archive.addFile(ArchiveFile('META-INF/container.xml', containerXml.length,
        utf8.encode(containerXml)));

    // 章节 HTML
    final manifestItems = <String>[];
    final spineItems = <String>[];
    for (int i = 0; i < chapters.length; i++) {
      final id = 'chapter${i + 1}';
      final href = '$id.xhtml';
      manifestItems.add(
          '<item id="$id" href="$href" media-type="application/xhtml+xml"/>');
      spineItems.add('<itemref idref="$id"/>');

      final html = _buildChapterHtml(chapters[i], i + 1);
      archive.addFile(
          ArchiveFile('OEBPS/$href', html.length, utf8.encode(html)));
    }

    // content.opf
    final manifestStr = manifestItems.join('\n    ');
    final spineStr = spineItems.join('\n    ');
    final opf = _buildOpf(title, author, manifestStr, spineStr);
    archive.addFile(ArchiveFile('OEBPS/content.opf', opf.length, utf8.encode(opf)));

    // toc.ncx (可选，但很多阅读器需要)
    final ncx = _buildNcx(title, chapters);
    archive.addFile(ArchiveFile('OEBPS/toc.ncx', ncx.length, utf8.encode(ncx)));

    return Uint8List.fromList(encoder.encode(archive));
  }

  /// EPUB → TXT 提取文字
  static Future<String> epubToTxt(Uint8List epubBytes) async {
    final decoder = ZipDecoder();
    final archive = decoder.decodeBytes(epubBytes);

    final buffer = StringBuffer();
    for (final file in archive.files) {
      if (!file.isFile) continue;
      final name = file.name.toLowerCase();
      if (!name.endsWith('.xhtml') && !name.endsWith('.html') && !name.endsWith('.htm')) {
        continue;
      }
      final content = utf8.decode(file.content);
      final text = _stripHtml(content);
      if (text.trim().isNotEmpty) {
        buffer.writeln(text.trim());
        buffer.writeln();
      }
    }
    return buffer.toString().trim();
  }

  // ---- 内部方法 ----

  static List<_Chapter> _splitChapters(List<String> lines) {
    final chapters = <_Chapter>[];
    int currentStart = 0;
    String? currentTitle;

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;

      final isChapter = _chapterPatterns.any((re) => re.hasMatch(line));
      if (isChapter) {
        if (currentTitle != null || currentStart < i) {
          final body = lines
              .sublist(currentStart, i)
              .where((l) => l.trim().isNotEmpty)
              .join('\n');
          if (body.trim().isNotEmpty) {
            chapters.add(_Chapter(
              title: currentTitle ?? '正文',
              body: body,
            ));
          }
        }
        currentTitle = line;
        currentStart = i + 1;
      } else if (currentStart == 0 && i == 0 && !isChapter) {
        // 文件开头没有章节标题
        currentTitle = '正文';
        currentStart = i;
      }
    }

    // 最后一章
    final body = lines
        .sublist(currentStart)
        .where((l) => l.trim().isNotEmpty)
        .join('\n');
    if (body.trim().isNotEmpty) {
      chapters.add(_Chapter(
        title: currentTitle ?? '正文',
        body: body,
      ));
    }

    return chapters;
  }

  static String _buildChapterHtml(_Chapter chapter, int index) {
    final escapedTitle = _escapeXml(chapter.title);
    final escapedBody = chapter.body
        .split('\n')
        .map((line) => '<p>${_escapeXml(line)}</p>')
        .join('\n');
    return '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml">
<head><title>$escapedTitle</title></head>
<body>
  <h2>$escapedTitle</h2>
  $escapedBody
</body>
</html>''';
  }

  static String _buildOpf(
      String title, String author, String manifest, String spine) {
    final escapedTitle = _escapeXml(title);
    final escapedAuthor = _escapeXml(author.isEmpty ? 'Unknown' : author);
    return '''<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" unique-identifier="book-id" version="2.0">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>$escapedTitle</dc:title>
    <dc:creator>$escapedAuthor</dc:creator>
    <dc:language>zh</dc:language>
    <dc:identifier id="book-id">urn:uuid:${DateTime.now().millisecondsSinceEpoch}</dc:identifier>
  </metadata>
  <manifest>
    <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
    $manifest
  </manifest>
  <spine toc="ncx">
    $spine
  </spine>
</package>''';
  }

  static String _buildNcx(String title, List<_Chapter> chapters) {
    final navPoints = <String>[];
    for (int i = 0; i < chapters.length; i++) {
      final escapedTitle = _escapeXml(chapters[i].title);
      navPoints.add('''    <navPoint id="nav-${i + 1}" playOrder="${i + 1}">
      <navLabel><text>$escapedTitle</text></navLabel>
      <content src="chapter${i + 1}.xhtml"/>
    </navPoint>''');
    }
    final escapedTitle = _escapeXml(title);
    return '''<?xml version="1.0" encoding="UTF-8"?>
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
  <head>
    <meta name="dtb:uid" content="urn:uuid:${DateTime.now().millisecondsSinceEpoch}"/>
  </head>
  <docTitle><text>$escapedTitle</text></docTitle>
  <navMap>
${navPoints.join('\n')}
  </navMap>
</ncx>''';
  }

  static String _stripHtml(String html) {
    return html
        .replaceAll(RegExp(r'<script[^>]*>.*?</script>', dotAll: true), '')
        .replaceAll(RegExp(r'<style[^>]*>.*?</style>', dotAll: true), '')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n');
  }

  static String _escapeXml(String s) {
    return s
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;');
  }
}

class _Chapter {
  final String title;
  final String body;
  _Chapter({required this.title, required this.body});
}
