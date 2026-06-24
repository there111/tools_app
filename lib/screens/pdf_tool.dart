import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import '../services/pdf_service.dart';
import '../utils/save_file.dart';

class PdfToolScreen extends StatefulWidget {
  const PdfToolScreen({super.key});

  @override
  State<PdfToolScreen> createState() => _PdfToolScreenState();
}

class _PdfToolScreenState extends State<PdfToolScreen> {
  String? _inputPath;
  Uint8List? _inputBytes;
  String? _inputName;
  bool _loading = false;
  int _pageCount = 0;
  double _scale = 2.0;
  Uint8List? _outputBytes;
  String? _outputName;
  bool _processing = false;
  double _progress = 0;
  String? _error;

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    setState(() {
      _inputPath = result.files.first.path;
      _inputBytes = result.files.first.bytes;
      _inputName = result.files.first.name;
      _outputBytes = null;
      _outputName = null;
      _error = null;
      _pageCount = 0;
      _loading = true;
    });

    try {
      final count = await PdfService.getPageCount(
        filePath: _inputPath,
        data: _inputBytes,
      );
      if (mounted) setState(() { _pageCount = count; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = '无法打开 PDF: $e'; _loading = false; });
    }
  }

  Future<void> _process() async {
    if (_inputPath == null && _inputBytes == null) return;
    setState(() { _processing = true; _progress = 0; _error = null; });

    try {
      final encoder = ZipEncoder();
      final archive = Archive();
      final baseName = p.basenameWithoutExtension(_inputName!);

      final pngs = await PdfService.renderAllPages(
        filePath: _inputPath,
        data: _inputBytes,
        scale: _scale,
        onProgress: (current, total) {
          if (mounted) setState(() => _progress = current / total);
        },
      );

      for (int i = 0; i < pngs.length; i++) {
        final filename = '${baseName}_${(i + 1).toString().padLeft(3, '0')}.png';
        archive.addFile(ArchiveFile(filename, pngs[i].length, pngs[i]));
      }

      final zipBytes = Uint8List.fromList(encoder.encode(archive));
      _outputBytes = zipBytes;
      _outputName = '${baseName}_images.zip';
    } catch (e) {
      _error = e.toString();
    }
    if (mounted) setState(() => _processing = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('PDF 工具箱')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _pickFile,
                      icon: const Icon(Icons.file_open),
                      label: Text(_inputName ?? '选择 PDF 文件'),
                    ),
                    if (_loading) ...[
                      const SizedBox(height: 12),
                      const LinearProgressIndicator(),
                    ],
                    if (_pageCount > 0) ...[
                      const SizedBox(height: 12),
                      Text('共 $_pageCount 页',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.grey)),
                    ],
                    if (_pageCount > 0) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Text('分辨率', style: TextStyle(fontSize: 14)),
                          Expanded(
                            child: Slider(
                              value: _scale,
                              min: 1.0, max: 4.0, divisions: 6,
                              label: '${_scale}x',
                              onChanged: (v) => setState(() => _scale = v),
                            ),
                          ),
                          Text('${_scale}x'),
                        ],
                      ),
                    ],
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _inputPath == null || _pageCount == 0 || _processing
                          ? null : _process,
                      icon: _processing
                          ? const SizedBox(width: 16, height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.play_arrow),
                      label: Text(_processing ? '处理中...' : '开始处理'),
                    ),
                    if (_processing) ...[
                      const SizedBox(height: 8),
                      LinearProgressIndicator(value: _progress),
                      Text('${(_progress * _pageCount).round()} / $_pageCount',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
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
