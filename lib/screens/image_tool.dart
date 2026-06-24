import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:archive/archive.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import '../services/image_service.dart';
import '../utils/save_file.dart';

class ImageToolScreen extends StatefulWidget {
  const ImageToolScreen({super.key});

  @override
  State<ImageToolScreen> createState() => _ImageToolScreenState();
}

class _ImageToolScreenState extends State<ImageToolScreen> {
  List<_ImageEntry> _entries = [];
  bool _processing = false;

  // 操作模式
  int _mode = 0; // 0=压缩, 1=分辨率, 2=底色, 3=格式转换

  // 压缩参数
  int _quality = 85;

  // 分辨率参数
  final _widthCtrl = TextEditingController();
  final _heightCtrl = TextEditingController();

  // 底色参数
  Color _bgColor = Colors.white;
  int _tolerance = 40;

  // 格式转换参数
  String _targetFormat = '.jpg';

  Future<void> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'webp', 'bmp'],
      allowMultiple: true,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    setState(() {
      _entries = result.files
          .where((f) => f.bytes != null)
          .map((f) => _ImageEntry(
                bytes: f.bytes!,
                name: f.name,
                originalSize: f.size,
              ))
          .toList();
    });
  }

  Future<void> _process() async {
    if (_entries.isEmpty) return;
    setState(() => _processing = true);

    try {
      for (final entry in _entries) {
        try {
          ImageToolResult result;
          switch (_mode) {
            case 0:
              result = ImageToolService.compress(entry.bytes, entry.name, quality: _quality);
              break;
            case 1:
              final w = int.tryParse(_widthCtrl.text);
              final h = int.tryParse(_heightCtrl.text);
              result = ImageToolService.resize(entry.bytes, entry.name,
                  width: w, height: h);
              break;
            case 2:
              result = ImageToolService.changeBackground(entry.bytes, entry.name,
                  r: (_bgColor.r * 255).round().clamp(0, 255),
                  g: (_bgColor.g * 255).round().clamp(0, 255),
                  b: (_bgColor.b * 255).round().clamp(0, 255),
                  tolerance: _tolerance);
              break;
            case 3:
              result = ImageToolService.convertFormat(
                  entry.bytes, entry.name, _targetFormat);
              break;
            default:
              continue;
          }
          entry.result = result;
        } catch (e) {
          entry.error = e.toString();
        }
      }
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<void> _saveAll() async {
    final completed = _entries.where((e) => e.result != null).toList();
    if (completed.isEmpty) return;

    if (completed.length == 1) {
      await _saveSingle(completed.first);
    } else {
      await _saveBatch(completed);
    }
  }

  Future<void> _saveSingle(_ImageEntry entry) async {
    await saveFile(entry.result!.bytes, entry.result!.filename);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已保存: ${entry.result!.filename}')),
      );
    }
  }

  Future<void> _saveBatch(List<_ImageEntry> entries) async {
    final encoder = ZipEncoder();
    final archive = Archive();

    for (final entry in entries) {
      archive.addFile(ArchiveFile(
        entry.result!.filename,
        entry.result!.bytes.length,
        entry.result!.bytes,
      ));
    }

    final zipBytes = Uint8List.fromList(encoder.encode(archive));
    await saveFile(zipBytes, 'processed_images.zip');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已保存 ${entries.length} 张图片到 processed_images.zip')),
      );
    }
  }

  String _totalStats() {
    final done = _entries.where((e) => e.result != null);
    if (done.isEmpty) return '';
    final orig = done.fold<int>(0, (s, e) => s + e.originalSize);
    final news = done.fold<int>(0, (s, e) => s + e.result!.newSize);
    final pct = ((1 - news / orig) * 100).round();
    return '${done.length} 张 · ${_formatSize(orig)} → ${_formatSize(news)} (${pct > 0 ? "-$pct" : "+${-pct}"}%)';
  }

  static String _formatSize(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
  }

  @override
  void dispose() {
    _widthCtrl.dispose();
    _heightCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('图片工具箱')),
      body: Column(
        children: [
          _buildModeBar(),
          _buildParams(),
          Expanded(child: _buildPreview()),
          _buildBottomBar(),
        ],
      ),
    );
  }

  Widget _buildModeBar() {
    final modes = ['压缩', '分辨率', '底色', '格式'];
    final icons = [Icons.compress, Icons.aspect_ratio, Icons.color_lens, Icons.swap_horiz];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: List.generate(4, (i) {
          final selected = _mode == i;
          return Expanded(
            child: Padding(
              padding: EdgeInsets.only(left: i > 0 ? 6.0 : 0),
              child: ChoiceChip(
                selected: selected,
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icons[i], size: 16),
                    const SizedBox(width: 4),
                    Text(modes[i], style: const TextStyle(fontSize: 13)),
                  ],
                ),
                onSelected: (_) => setState(() => _mode = i),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildParams() {
    switch (_mode) {
      case 0:
        return _buildQualitySlider();
      case 1:
        return _buildResizeInputs();
      case 2:
        return _buildBgColorPicker();
      case 3:
        return _buildFormatPicker();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildQualitySlider() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          const Text('质量', style: TextStyle(fontSize: 14)),
          Expanded(
            child: Slider(
              value: _quality.toDouble(),
              min: 10,
              max: 100,
              divisions: 90,
              label: '$_quality',
              onChanged: (v) => setState(() => _quality = v.round()),
            ),
          ),
          SizedBox(
              width: 40,
              child: Text('$_quality', textAlign: TextAlign.right)),
        ],
      ),
    );
  }

  Widget _buildResizeInputs() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        children: [
          const Text('宽', style: TextStyle(fontSize: 14)),
          const SizedBox(width: 8),
          SizedBox(
            width: 80,
            child: TextField(
              controller: _widthCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                isDense: true,
                hintText: 'auto',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 16),
          const Text('高', style: TextStyle(fontSize: 14)),
          const SizedBox(width: 8),
          SizedBox(
            width: 80,
            child: TextField(
              controller: _heightCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                isDense: true,
                hintText: 'auto',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          const Text('px', style: TextStyle(fontSize: 12, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildBgColorPicker() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        children: [
          const Text('背景色', style: TextStyle(fontSize: 14)),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: () {
              showDialog(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('选择背景色'),
                  content: SingleChildScrollView(
                    child: ColorPicker(
                      pickerColor: _bgColor,
                      onColorChanged: (c) => setState(() => _bgColor = c),
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('确定'),
                    ),
                  ],
                ),
              );
            },
            child: Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                color: _bgColor,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.grey),
              ),
            ),
          ),
          const SizedBox(width: 24),
          const Text('容差', style: TextStyle(fontSize: 14)),
          Expanded(
            child: Slider(
              value: _tolerance.toDouble(),
              min: 10, max: 100, divisions: 18,
              onChanged: (v) => setState(() => _tolerance = v.round()),
            ),
          ),
          Text('$_tolerance'),
        ],
      ),
    );
  }

  Widget _buildFormatPicker() {
    const formats = ['.jpg', '.png', '.webp'];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        children: [
          const Text('转为', style: TextStyle(fontSize: 14)),
          const SizedBox(width: 12),
          SegmentedButton<String>(
            segments: formats
                .map((f) => ButtonSegment<String>(value: f, label: Text(f)))
                .toList(),
            selected: {_targetFormat},
            onSelectionChanged: (s) => setState(() => _targetFormat = s.first),
          ),
        ],
      ),
    );
  }

  Widget _buildPreview() {
    if (_entries.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add_photo_alternate, size: 64,
                color: Theme.of(context).colorScheme.onSurface.withAlpha(60)),
            const SizedBox(height: 12),
            const Text('点击下方按钮选择图片'),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemCount: _entries.length,
      itemBuilder: (ctx, i) {
        final entry = _entries[i];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.memory(
                    entry.bytes,
                    width: 60, height: 60, fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const Icon(Icons.broken_image),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(entry.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                      const SizedBox(height: 4),
                      if (entry.result != null)
                        Text(
                          '${_formatSize(entry.originalSize)} → ${_formatSize(entry.result!.newSize)} (${(entry.result!.ratio * 100).toStringAsFixed(0)}%)',
                          style: TextStyle(fontSize: 12, color: Colors.green.shade600),
                        )
                      else if (entry.error != null)
                        Text(entry.error!, style: const TextStyle(fontSize: 11, color: Colors.red))
                      else
                        Text(_formatSize(entry.originalSize),
                            style: TextStyle(fontSize: 12,
                                color: Theme.of(context).colorScheme.onSurface.withAlpha(150))),
                    ],
                  ),
                ),
                if (entry.result != null)
                  Icon(Icons.check_circle, color: Colors.green.shade600, size: 22),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildBottomBar() {
    final stats = _totalStats();
    final completed = _entries.where((e) => e.result != null).length;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (stats.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(stats, style: const TextStyle(fontSize: 13)),
              ),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _entries.isEmpty ? null : _pickFiles,
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(_entries.isEmpty ? '选择图片' : '添加更多 (${_entries.length})'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _entries.isEmpty || _processing ? null : _process,
                    icon: _processing
                        ? const SizedBox(width: 16, height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.play_arrow, size: 18),
                    label: const Text('处理'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: completed == 0 ? null : _saveAll,
                    icon: const Icon(Icons.download, size: 18),
                    label: Text(completed > 1 ? '打包下载' : '保存'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ImageEntry {
  final Uint8List bytes;
  final String name;
  final int originalSize;
  ImageToolResult? result;
  String? error;

  _ImageEntry({
    required this.bytes,
    required this.name,
    required this.originalSize,
  });
}
