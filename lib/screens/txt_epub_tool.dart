import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import '../services/epub_service.dart';
import '../utils/save_file.dart';

class TxtEpubToolScreen extends StatefulWidget {
  const TxtEpubToolScreen({super.key});

  @override
  State<TxtEpubToolScreen> createState() => _TxtEpubToolScreenState();
}

class _TxtEpubToolScreenState extends State<TxtEpubToolScreen> {
  int _direction = 0; // 0=TXT→EPUB, 1=EPUB→TXT
  Uint8List? _inputBytes;
  String? _inputName;
  Uint8List? _outputBytes;
  String? _outputName;
  bool _processing = false;
  String? _error;
  final _authorCtrl = TextEditingController();

  Future<void> _pickInput() async {
    final exts = _direction == 0 ? ['txt'] : ['epub'];
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: exts,
      withData: true,
    );
    if (result == null || result.files.isEmpty || result.files.first.bytes == null) return;
    setState(() {
      _inputBytes = result.files.first.bytes;
      _inputName = result.files.first.name;
      _outputBytes = null;
      _outputName = null;
      _error = null;
    });
  }

  Future<void> _convert() async {
    if (_inputBytes == null) return;
    setState(() { _processing = true; _error = null; });

    try {
      if (_direction == 0) {
        // TXT → EPUB
        final content = _decodeText(_inputBytes!);
        final baseName = p.basenameWithoutExtension(_inputName!);
        final epubBytes = await EpubService.txtToEpub(
          content,
          baseName,
          author: _authorCtrl.text.trim(),
        );
        _outputBytes = epubBytes;
        _outputName = '$baseName.epub';
      } else {
        // EPUB → TXT
        final text = await EpubService.epubToTxt(_inputBytes!);
        final baseName = p.basenameWithoutExtension(_inputName!);
        _outputBytes = Uint8List.fromList(utf8.encode(text));
        _outputName = '$baseName.txt';
      }
    } catch (e) {
      _error = e.toString();
    }
    if (mounted) setState(() => _processing = false);
  }

  String _decodeText(Uint8List raw) {
    // 检测 BOM
    if (raw.length >= 3 && raw[0] == 0xEF && raw[1] == 0xBB && raw[2] == 0xBF) {
      return utf8.decode(raw.sublist(3));
    }
    if (raw.length >= 2 && raw[0] == 0xFF && raw[1] == 0xFE) {
      return (Encoding.getByName('utf-16')!).decode(raw.sublist(2));
    }
    if (raw.length >= 2 && raw[0] == 0xFE && raw[1] == 0xFF) {
      return (Encoding.getByName('utf-16')!).decode(raw.sublist(2));
    }
    // fallback: 尝试 UTF-8，失败则用 GBK
    try {
      return utf8.decode(raw);
    } catch (_) {
      try {
        return (Encoding.getByName('gbk')!).decode(raw);
      } catch (_) {
        return utf8.decode(raw, allowMalformed: true);
      }
    }
  }

  @override
  void dispose() {
    _authorCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('TXT ↔ EPUB')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, label: Text('TXT → EPUB')),
                ButtonSegment(value: 1, label: Text('EPUB → TXT')),
              ],
              selected: {_direction},
              onSelectionChanged: (s) => setState(() => _direction = s.first),
            ),
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _pickInput,
                      icon: const Icon(Icons.file_open),
                      label: Text(_inputName ?? '选择文件'),
                    ),
                    if (_direction == 0 && _inputBytes != null) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: _authorCtrl,
                        decoration: const InputDecoration(
                          labelText: '作者（可选）',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _inputBytes == null || _processing ? null : _convert,
                      icon: _processing
                          ? const SizedBox(width: 16, height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.swap_horiz),
                      label: Text(_processing ? '转换中...' : '开始转换'),
                    ),
                  ],
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Card(
                color: Colors.red.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(_error!, style: const TextStyle(color: Colors.red)),
                ),
              ),
            ],
            if (_outputBytes != null) ...[
              const SizedBox(height: 12),
              Card(
                color: Colors.green.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle, color: Colors.green.shade600),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text('已完成: $_outputName',
                            style: TextStyle(color: Colors.green.shade700)),
                      ),
                      FilledButton.tonal(
                        onPressed: () => saveFile(_outputBytes!, _outputName!),
                        child: const Text('下载'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
