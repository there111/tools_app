import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';

Future<void> saveFile(Uint8List bytes, String filename) async {
  final dir = await getApplicationDocumentsDirectory();
  final outDir = Directory('${dir.path}/tools_output');
  if (!await outDir.exists()) await outDir.create(recursive: true);
  await File('${outDir.path}/$filename').writeAsBytes(bytes);
}
