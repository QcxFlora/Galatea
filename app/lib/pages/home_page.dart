/// 首界面：扁平 3D 舞台上的项目入口。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../editor/editor_page.dart';
import '../engine/spring.dart';
import '../platform/orientation.dart';
import '../models/graph.dart';
import '../storage/store.dart';
import '../theme.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<File> _recent = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    lockPortrait();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final list = await ProjectStore.list();
      if (!mounted) return;
      setState(() {
        _recent = list;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _openEditor(Story story, {File? file}) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => EditorPage(story: story, file: file)),
    );
    _refresh();
  }

  Future<void> _newProject() async {
    final controller = TextEditingController(text: '未命名剧本');
    final title = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: GColors.panel,
        title: const Text('新建剧本'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '给作品起个名字'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('开始'),
          ),
        ],
      ),
    );
    if (title == null || title.isEmpty) return;
    final story = Story.blank(title);
    final f = await ProjectStore.save(story);
    await _openEditor(story, file: f);
  }

  Future<void> _openSample(String asset, String fileName) async {
    try {
      final raw = await rootBundle.loadString(asset);
      final decoded = jsonDecode(raw);
      if (decoded is! Map) throw const FormatException('示例文件损坏');
      final story = Story.fromJson(Map<String, dynamic>.from(decoded));
      final f = await ProjectStore.save(story, fileName: fileName);
      await _openEditor(story, file: f);
    } catch (e) {
      _toast('打开示例失败：$e');
    }
  }

  Future<void> _openDemo() =>
      _openSample('assets/samples/rain.gala.json', '示例-雨声与自动门.gala.json');

  Future<void> _openArknights() =>
      _openSample('assets/samples/arknights_demo.json', '示例-博士的加班报告.gala.json');

  Future<void> _import() async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: GColors.panel,
        title: const Text('导入剧本'),
        content: SizedBox(
          width: 420,
          child: TextField(
            controller: controller,
            maxLines: 9,
            style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
            decoration: const InputDecoration(
                hintText: '把 .gala.json 的内容粘贴到这里'),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('导入'),
          ),
        ],
      ),
    );
    if (text == null || text.trim().isEmpty) return;
    try {
      final f = await ProjectStore.importText(text);
      final story = await ProjectStore.load(f);
      await _openEditor(story, file: f);
    } catch (e) {
      _toast('导入失败：$e');
    }
  }

  Future<void> _openFile(File f) async {
    try {
      final story = await ProjectStore.load(f);
      await _openEditor(story, file: f);
    } catch (e) {
      _toast('打开失败：$e');
    }
  }

  Future<void> _deleteFile(File f) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: GColors.panel,
        title: const Text('删除这个项目？'),
        content: Text(f.uri.pathSegments.last, style: const TextStyle(fontSize: 12)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: GColors.err)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ProjectStore.delete(f);
    _refresh();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(child: _StageBackground()),
          SafeArea(
            bottom: false,
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                  28, 24, 28, 32 + MediaQuery.of(context).viewPadding.bottom),
              children: [
                const _TitleBlock(),
                const SizedBox(height: 30),
                _EntryCard(
                  icon: '✦',
                  color: GColors.accent,
                  title: '《博士的加班报告》',
                  subtitle: '明日方舟同人 · 24 方块 · 3 结局 · 演示角色与立绘方块',
                  highlight: true,
                  onTap: _openArknights,
                ),
                const SizedBox(height: 12),
                _EntryCard(
                  icon: '✦',
                  color: GColors.accent2,
                  title: '《雨声与自动门》',
                  subtitle: '原创短篇 · 20 节点 · 3 结局',
                  onTap: _openDemo,
                ),
                const SizedBox(height: 12),
                _EntryCard(
                  icon: '✎',
                  color: GColors.accent,
                  title: '新建剧本',
                  subtitle: '从一张空白画布开始长故事',
                  onTap: _newProject,
                ),
                const SizedBox(height: 12),
                _EntryCard(
                  icon: '⇩',
                  color: GColors.ok,
                  title: '导入 JSON',
                  subtitle: '粘贴 .gala.json 即可载入',
                  onTap: _import,
                ),
                const SizedBox(height: 30),
                Row(
                  children: [
                    const Text('最近的剧本',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: GColors.dim)),
                    const Spacer(),
                    if (_loading)
                      const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 2)),
                  ],
                ),
                const SizedBox(height: 10),
                if (!_loading && _recent.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 18),
                    child: Text('还没有项目，先新建一个吧',
                        style: TextStyle(fontSize: 12.5, color: GColors.dim)),
                  ),
                for (final f in _recent)
                  _ProjectTile(
                    file: f,
                    onTap: () => _openFile(f),
                    onLongPress: () => _deleteFile(f),
                  ),
                const SizedBox(height: 26),
                const Center(
                  child: Text('GALATEA 0.1.0 · GPL-3.0 · 动画手感致敬 lilt',
                      style: TextStyle(fontSize: 10.5, color: Color(0xFF5A6478))),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 背景：渐变夜色 + 伪 3D 网格地面（Transform 做透视）
class _StageBackground extends StatelessWidget {
  const _StageBackground();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF0A0D14), GColors.bg, Color(0xFF070A10)],
            ),
          ),
        ),
        // 来自星尘：一组极淡的同心轨道
        Positioned(
          right: -160,
          top: -120,
          child: Container(
            width: 520,
            height: 520,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withOpacity(0.055)),
            ),
            child: Center(
              child: Container(
                width: 340,
                height: 340,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white.withOpacity(0.04)),
                ),
              ),
            ),
          ),
        ),
        // 网格地面
        Positioned(
          left: -200,
          right: -200,
          bottom: -120,
          height: 320,
          child: Transform(
            alignment: Alignment.bottomCenter,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.0015)
              ..rotateX(1.15),
            child: CustomPaint(painter: _GridPainter()),
          ),
        ),
      ],
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.045)
      ..strokeWidth = 1;
    const step = 56.0;
    for (var x = 0.0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = 0.0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) => false;
}

class _TitleBlock extends StatelessWidget {
  const _TitleBlock();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SpringBuilder(
          begin: -110,
          target: 0,
          preset: SpringPreset.smooth,
          builder: (_, dy) => Transform.translate(
            offset: Offset(0, dy),
            child: Column(
              children: [
                const Text(
                  'GALATEA',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 40,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 7,
                    height: 1,
                    color: GColors.textStrong,
                  ),
                ),
                const SizedBox(height: 12),
                Container(width: 44, height: 3, color: GColors.accent),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text('MIND-MAP GALGAME ENGINE',
            style: labelStyle(color: GColors.dim, size: 10)),
        const SizedBox(height: 10),
        const Text('剧情是一张图 · 连线即分支 · 一键打包成游戏',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: GColors.dim, height: 1.6)),
      ],
    );
  }
}

class _EntryCard extends StatelessWidget {
  final String icon;
  final Color color;
  final String title;
  final String subtitle;
  final bool highlight;
  final VoidCallback onTap;

  const _EntryCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: GColors.panel,
          border: Border.all(color: GColors.line, width: 1),
        ),
        child: Row(
          children: [
            // 左侧 3px 竖线：唯一彩色只给「首要操作」
            Container(
              width: 3,
              height: 38,
              color: highlight ? GColors.accent : GColors.dim,
            ),
            const SizedBox(width: 14),
            Text(icon,
                style: TextStyle(
                    fontSize: 13,
                    color: highlight ? GColors.accent : GColors.dim)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.3,
                          color: GColors.textStrong)),
                  const SizedBox(height: 4),
                  Text(subtitle,
                      style: const TextStyle(
                          fontSize: 11, color: GColors.dim, height: 1.4)),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward, color: GColors.dim, size: 15),
          ],
        ),
      ),
    );
  }
}

class _ProjectTile extends StatelessWidget {
  final File file;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _ProjectTile({
    required this.file,
    required this.onTap,
    required this.onLongPress,
  });

  String get _name {
    final n = file.uri.pathSegments.last;
    return n.endsWith('.gala.json') ? n.substring(0, n.length - 10) : n;
  }

  String get _when {
    try {
      final t = file.lastModifiedSync();
      return '${t.month}/${t.day} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: GColors.panel,
          borderRadius: BorderRadius.zero,
          border: Border.all(color: GColors.line),
        ),
        child: Row(
          children: [
            const Icon(Icons.account_tree_outlined,
                size: 17, color: GColors.dim),
            const SizedBox(width: 11),
            Expanded(
              child: Text(_name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13.5, color: GColors.text)),
            ),
            Text(_when,
                style: const TextStyle(fontSize: 10.5, color: GColors.dim)),
          ],
        ),
      ),
    );
  }
}