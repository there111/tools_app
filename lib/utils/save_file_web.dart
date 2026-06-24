import 'dart:typed_data';
// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

Future<void> saveFile(Uint8List bytes, String filename) async {
  final blob = html.Blob([bytes]);
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url);
  anchor.setAttribute('download', filename);
  anchor.click();
  html.Url.revokeObjectUrl(url);
}
