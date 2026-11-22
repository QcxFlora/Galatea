/// 书柜 —— 主界面（视觉参考《来自星尘》的记录/道具界面）
///
/// 语言：浅色渐变底 + 噪点 · 大圆角白卡片 · 细线分隔 · 青色点缀 · 大量留白
library;

import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../engine/game_launcher.dart';
import '../engine/spring.dart';
import '../editor/editor_page.dart';
import '../platform/orientation.dart';
import '../storage/store.dart';
import '../theme.dart';
import '../ui/depth.dart';
import '../version.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<File> _books = const [];
  Map<String, String> _titles = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    lockPortrait();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final list = await ProjectStore.listGal();
      final titles = <String, String>{};
      for (final f in list) {
        titles[f.path] = ProjectStore.titleOf(f);
      }
      if (!mounted) return;
      setState(() {
        _books = list;
        _titles = titles;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _open(LoadedProject p) async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => EditorPage(project: p)));
    _refresh();
  }

  Future<void> _newBook() async {
    final controller = TextEditingController(text: '未命名剧本');
    final title = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('写一本新的'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '作品名'),
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
    final p = await ProjectStore.create(title);
    await _open(p);
  }

  /// 把最近一本书交给 Godot 运行时（3D 演出）
  Future<void> _play3d() async {
    final books = await ProjectStore.listGal();
    if (books.isEmpty) {
      _toast('书柜还是空的，先放一本书进来');
      return;
    }
    final msg = await launchWithProject(books.first.path);
    _toast(msg);
  }

  Future<void> _openSample() async {
    try {
      final p = await ProjectStore.installSample(
          'assets/samples/arknights_demo.gal', '博士的加班报告.gal');
      await _open(p);
    } catch (e) {
      _toast('打开示例失败：$e');
    }
  }

  Future<void> _import() async {
    try {
      final res = await FilePicker.platform
          .pickFiles(type: FileType.any, allowMultiple: false);
      final path = res?.files.single.path;
      if (path == null) return;
      final p = await ProjectStore.importFrom(File(path));
      await _open(p);
    } catch (e) {
      _toast('导入失败：$e');
    }
  }

  Future<void> _delete(File f) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('从书柜取下这本？'),
        content: Text(_titles[f.path] ?? f.uri.pathSegments.last,
            style: const TextStyle(fontSize: 13)),
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
    final bottom = MediaQuery.of(context).viewPadding.bottom;
    return Scaffold(
      backgroundColor: GColors.bg,
      body: DepthScene(
        maxTilt: 3.5,
        child: Stack(
        children: [
          // 远景层：退后一层，带漂浮轨道
          const Positioned.fill(
            child: DepthBackdrop(
              depth: 1.0,
              child: _PaperBackground(),
            ),
          ),
          const Positioned.fill(child: DepthRails(depth: 0.7)),
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                _TopBar(
                  onNew: _newBook,
                  onImport: _import,
                  onSample: _openSample,
                  onPlay3d: _play3d,
                ),
                Expanded(
                  child: _loading
                      ? const Center(
                          child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2)))
                      : ListView(
                          padding: EdgeInsets.fromLTRB(20, 6, 20, 26 + bottom),
                          children: [
                            if (_books.isEmpty)
                              _EmptyState(onSample: _openSample, onImport: _import)
                            else
                              for (var i = 0; i < _books.length; i++)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 14),
                                  child: _RecordCard(
                                    title: _titles[_books[i].path] ??
                                        _books[i].uri.pathSegments.last,
                                    sizeKb: _books[i].existsSync()
                                        ? (_books[i].lengthSync() / 1024).round()
                                        : 0,
                                    seed: i,
                                    latest: i == 0,
                                    onTap: () async {
                                      try {
                                        await _open(await ProjectStore.open(
                                            _books[i]));
                                      } catch (e) {
                                        _toast('打不开：$e');
                                      }
                                    },
                                    onLongPress: () => _delete(_books[i]),
                                  ),
                                ),
                            const SizedBox(height: 6),
                            _StatsRow(count: _books.length),
                            const SizedBox(height: 18),
                            Center(
                              child: Text(
                                'GALATEA $kAppVersion   ·   .gal',
                                style: const TextStyle(
                                    fontSize: 10,
                                    color: GColors.dim,
                                    letterSpacing: 1.4),
                              ),
                            ),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ 顶部栏

class _TopBar extends StatelessWidget {
  final VoidCallback onNew;
  final VoidCallback onImport;
  final VoidCallback onSample;
  final VoidCallback onPlay3d;

  const _TopBar({
    required this.onNew,
    required this.onImport,
    required this.onSample,
    required this.onPlay3d,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      child: Row(
        children: [
          // 左上角圆底 X（参考图的位置，这里作为"收起"视觉锚点）
          SpringBuilder(
            begin: -30,
            target: 0,
            preset: SpringPreset.smooth,
            builder: (_, dy) => Transform.translate(
              offset: Offset(0, dy),
              child: Container(
                width: 38,
                height: 38,
                decoration: const BoxDecoration(
                  color: GColors.paper,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                        color: Color(0x14000000), blurRadius: 10, offset: Offset(0, 2)),
                  ],
                ),
                child: const Icon(Icons.auto_stories_outlined,
                    size: 18, color: GColors.text),
              ),
            ),
          ),
          const SizedBox(width: 12),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('书柜',
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: GColors.textStrong,
                      letterSpacing: 2)),
              Text('MY SHELF',
                  style: TextStyle(
                      fontSize: 8.5,
                      color: GColors.dim,
                      letterSpacing: 2.4)),
            ],
          ),
          const Spacer(),
          _RoundAction(icon: Icons.add, onTap: onNew, primary: true),
          const SizedBox(width: 8),
          _RoundAction(icon: Icons.folder_open, onTap: onImport),
          const SizedBox(width: 8),
          _RoundAction(icon: Icons.download_outlined, onTap: onSample),
          const SizedBox(width: 8),
          _RoundAction(icon: Icons.view_in_ar, onTap: onPlay3d),
        ],
      ),
    );
  }
}

class _RoundAction extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool primary;

  const _RoundAction({
    required this.icon,
    required this.onTap,
    this.primary = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: primary ? GColors.accent : GColors.paper,
          shape: BoxShape.circle,
          boxShadow: const [
            BoxShadow(
                color: Color(0x14000000), blurRadius: 10, offset: Offset(0, 2)),
          ],
        ),
        child: Icon(icon,
            size: 18, color: primary ? Colors.white : GColors.text),
      ),
    );
  }
}

// ------------------------------------------------------------------ 记录卡

class _RecordCard extends StatelessWidget {
  final String title;
  final int sizeKb;
  final int seed;
  final bool latest;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _RecordCard({
    required this.title,
    required this.sizeKb,
    required this.seed,
    required this.latest,
    required this.onTap,
    required this.onLongPress,
  });

  /// 封面色（低饱和，按标题散列）
  List<Color> get _cover {
    const sets = [
      [Color(0xFF6B7BB8), Color(0xFF3C4A78), Color(0xFF8E9BD0)],
      [Color(0xFF7A8FA6), Color(0xFF46596E), Color(0xFF9DB0C2)],
      [Color(0xFF8A7A9E), Color(0xFF53465F), Color(0xFFA897BA)],
      [Color(0xFF5F8A82), Color(0xFF36544F), Color(0xFF87B4AB)],
    ];
    return sets[title.hashCode.abs() % sets.length];
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: DepthCard(
        elevation: 10,
        child: Container(
        height: 148,
        decoration: BoxDecoration(
          color: GColors.paper,
          borderRadius: const BorderRadius.all(Radius.circular(14)),
          border: Border.all(color: GColors.lineLight),
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          children: [
            // 左：文字区
            Expanded(
              flex: 5,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 10, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (latest)
                      Container(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: GColors.accent.withOpacity(0.12),
                          borderRadius:
                              const BorderRadius.all(Radius.circular(20)),
                        ),
                        child: const Text('最近记录',
                            style: TextStyle(
                                fontSize: 9,
                                color: GColors.accent,
                                letterSpacing: 0.8)),
                      ),
                    const Spacer(),
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w600,
                        height: 1.25,
                        color: GColors.textStrong,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.cloud_done_outlined,
                            size: 13, color: GColors.dim),
                        const SizedBox(width: 5),
                        Text('云端状态：已归档 · $sizeKb KB',
                            style: const TextStyle(
                                fontSize: 10, color: GColors.dim)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            // 右：封面拼贴
            Expanded(
              flex: 4,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: _cover,
                      ),
                    ),
                  ),
                  // 两道斜切色带（还原参考图的拼贴感）
                  Positioned(
                    right: -20,
                    top: -30,
                    bottom: -30,
                    child: Transform.rotate(
                      angle: math.pi / 9,
                      child: Container(
                        width: 54,
                        color: Colors.white.withOpacity(0.14),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 44,
                    top: -30,
                    bottom: -30,
                    child: Transform.rotate(
                      angle: math.pi / 9,
                      child: Container(
                        width: 16,
                        color: Colors.white.withOpacity(0.08),
                      ),
                    ),
                  ),
                  // 右下角书名首字
                  Positioned(
                    right: 12,
                    bottom: 8,
                    child: Text(
                      title.isEmpty ? '?' : title.characters.first,
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w700,
                        color: Colors.white.withOpacity(0.85),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }
}

// ------------------------------------------------------------------ 统计条

class _StatsRow extends StatelessWidget {
  final int count;

  const _StatsRow({required this.count});

  @override
  Widget build(BuildContext context) {
    final items = [
      (count.toString(), '作品'),
      ('1', '示例'),
      ('13', '方块类型'),
      ('37', '测试'),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
      decoration: BoxDecoration(
        color: GColors.paper.withOpacity(0.7),
        borderRadius: const BorderRadius.all(Radius.circular(14)),
        border: Border.all(color: GColors.lineLight),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          for (var i = 0; i < items.length; i++) ...[
            Column(
              children: [
                Text(items[i].$1,
                    style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w300,
                        color: GColors.textStrong,
                        height: 1)),
                const SizedBox(height: 4),
                Text(items[i].$2,
                    style: const TextStyle(
                        fontSize: 10, color: GColors.dim, letterSpacing: 1.2)),
              ],
            ),
            if (i < items.length - 1)
              Container(width: 1, height: 30, color: GColors.line),
          ],
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onSample;
  final VoidCallback onImport;

  const _EmptyState({required this.onSample, required this.onImport});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 44),
      child: Column(
        children: [
          Container(
            width: 74,
            height: 74,
            decoration: BoxDecoration(
              color: GColors.paper,
              shape: BoxShape.circle,
              border: Border.all(color: GColors.lineLight),
            ),
            child: const Icon(Icons.auto_stories,
                size: 30, color: GColors.accent),
          ),
          const SizedBox(height: 18),
          const Text('书柜是空的',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: GColors.textStrong)),
          const SizedBox(height: 6),
          const Text('放一本书进来，或者先看看示例',
              style: TextStyle(fontSize: 12, color: GColors.dim)),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _PillButton(label: '打开示例', onTap: onSample, primary: true),
              const SizedBox(width: 10),
              _PillButton(label: '导入 .gal', onTap: onImport),
            ],
          ),
        ],
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool primary;

  const _PillButton({
    required this.label,
    required this.onTap,
    this.primary = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: primary ? GColors.accent : GColors.paper,
          borderRadius: const BorderRadius.all(Radius.circular(22)),
          border: Border.all(
              color: primary ? GColors.accent : GColors.line),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
                color: primary ? Colors.white : GColors.text)),
      ),
    );
  }
}

// ------------------------------------------------------------------ 背景

class _PaperBackground extends StatelessWidget {
  const _PaperBackground();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFFDFDFE), Color(0xFFF1F3F6), Color(0xFFE4E8EE)],
            ),
          ),
        ),
        Positioned.fill(child: CustomPaint(painter: _GrainPainter())),
        // 右上角极淡的青色光晕（参考图的氛围）
        Positioned(
          right: -80,
          top: -60,
          child: Container(
            width: 280,
            height: 280,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [
                GColors.accent.withOpacity(0.10),
                Colors.transparent,
              ]),
            ),
          ),
        ),
      ],
    );
  }
}

class _GrainPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // 细网格 + 噪点（用规则点阵模拟，性能友好）
    final p = Paint()..color = const Color(0x08000000);
    for (var y = 0.0; y < size.height; y += 4) {
      for (var x = 0.0; x < size.width; x += 4) {
        if (((x * 7 + y * 13) % 37) < 2) canvas.drawRect(Rect.fromLTWH(x, y, 1, 1), p);
      }
    }
  }

  @override
  bool shouldRepaint(_GrainPainter old) => false;
}