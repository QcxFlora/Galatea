/// 书柜 —— 主界面。
///
/// 一个 `.gal` 就是一本作品集，像书一样立在架子上：
/// 竖排的书脊、按标题取的灰阶色、底部一排书架板。
library;

import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../editor/editor_page.dart';
import '../engine/spring.dart';
import '../platform/orientation.dart';
import '../storage/store.dart';
import '../theme.dart';
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
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => EditorPage(project: p)),
    );
    _refresh();
  }

  Future<void> _newBook() async {
    final controller = TextEditingController(text: '未命名剧本');
    final title = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: GColors.panel,
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
      final res = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
      );
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
        backgroundColor: GColors.panel,
        title: const Text('从书柜取下这本书？'),
        content: Text(_titles[f.path] ?? f.uri.pathSegments.last,
            style: const TextStyle(fontSize: 12)),
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
      backgroundColor: GColors.ink,
      body: Stack(
        children: [
          const Positioned.fill(child: _ShelfBackground()),
          SafeArea(
            bottom: false,
            child: ListView(
              padding: EdgeInsets.fromLTRB(20, 18, 20, 24 + bottom),
              children: [
                _Header(
                  onNew: _newBook,
                  onImport: _import,
                  onSample: _openSample,
                ),
                const SizedBox(height: 22),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Center(
                        child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))),
                  )
                else if (_books.isEmpty)
                  const _EmptyShelf()
                else
                  _Shelf(
                    books: _books,
                    titles: _titles,
                    onTap: (f) async {
                      try {
                        await _open(await ProjectStore.open(f));
                      } catch (e) {
                        _toast('打不开：$e');
                      }
                    },
                    onLongPress: _delete,
                  ),
                const SizedBox(height: 22),
                Center(
                  child: Text(
                    'GALATEA ${kAppVersion}  ·  .gal',
                    style: const TextStyle(
                        fontSize: 10, color: Color(0xFF5A6478), letterSpacing: 1),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ 顶部

class _Header extends StatelessWidget {
  final VoidCallback onNew;
  final VoidCallback onImport;
  final VoidCallback onSample;

  const _Header({
    required this.onNew,
    required this.onImport,
    required this.onSample,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SpringBuilder(
          begin: -40,
          target: 0,
          preset: SpringPreset.smooth,
          builder: (_, dy) => Transform.translate(
            offset: Offset(0, dy),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Text(
                  'GALATEA',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 5,
                    height: 1,
                    color: GColors.textStrong,
                  ),
                ),
                const SizedBox(width: 10),
                Container(width: 22, height: 3, color: GColors.accent),
                const Spacer(),
                Text('${kAppVersion}',
                    style: const TextStyle(
                        fontSize: 9.5, color: GColors.dim, letterSpacing: 1)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text('我的书柜 · 每一本都是可以玩的故事',
            style: labelStyle(color: GColors.dim, size: 10)),
        const SizedBox(height: 16),
        Row(
          children: [
            _ActionChip(
              icon: Icons.add,
              label: '新建',
              accent: true,
              onTap: onNew,
            ),
            const SizedBox(width: 8),
            _ActionChip(
              icon: Icons.folder_open,
              label: '导入 .gal',
              onTap: onImport,
            ),
            const SizedBox(width: 8),
            _ActionChip(
              icon: Icons.auto_stories,
              label: '示例',
              onTap: onSample,
            ),
          ],
        ),
      ],
    );
  }
}

class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool accent;
  final VoidCallback onTap;

  const _ActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
    this.accent = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = accent ? GColors.accent : GColors.dim;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: GColors.panel,
          border: Border.all(color: accent ? GColors.accent : GColors.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    fontSize: 11,
                    color: accent ? GColors.textStrong : GColors.text,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4)),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ 书架

class _Shelf extends StatelessWidget {
  final List<File> books;
  final Map<String, String> titles;
  final void Function(File) onTap;
  final void Function(File) onLongPress;

  const _Shelf({
    required this.books,
    required this.titles,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      itemCount: books.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 14,
        crossAxisSpacing: 14,
        childAspectRatio: 0.82,
      ),
      itemBuilder: (_, i) {
        final f = books[i];
        return _CoverCard(
          title: titles[f.path] ?? f.uri.pathSegments.last,
          index: i,
          sizeKb: f.existsSync() ? (f.lengthSync() / 1024).round() : 0,
          onTap: () => onTap(f),
          onLongPress: () => onLongPress(f),
        );
      },
    );
  }
}

class _CoverCard extends StatefulWidget {
  final String title;
  final int index;
  final int sizeKb;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _CoverCard({
    required this.title,
    required this.index,
    required this.sizeKb,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  State<_CoverCard> createState() => _CoverCardState();
}

class _CoverCardState extends State<_CoverCard> {
  bool _down = false;

  /// 按标题散列取一组冷色（同一本书永远同色）
  List<Color> get _coverGradient {
    final h = widget.title.hashCode.abs();
    const palettes = [
      [Color(0xFF232A38), Color(0xFF10141C)],
      [Color(0xFF2B2334), Color(0xFF14101A)],
      [Color(0xFF1F2A2A), Color(0xFF0E1414)],
      [Color(0xFF2E2620), Color(0xFF16110D)],
      [Color(0xFF242433), Color(0xFF111119)],
    ];
    return palettes[h % palettes.length];
  }

  Color get _edge => const [GColors.accent, Color(0xFFD6A3A0), Color(0xFFB8895F)][
      (widget.title.hashCode.abs() ~/ 7) % 3];

  @override
  Widget build(BuildContext context) {
    final first = widget.title.isEmpty ? '?' : widget.title.characters.first;
    return GestureDetector(
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      child: AnimatedScale(
        scale: _down ? 0.97 : 1,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: Container(
          decoration: BoxDecoration(
            color: GColors.panel,
            border: Border.all(color: GColors.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 封面
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: _coverGradient,
                    ),
                  ),
                  child: Stack(
                    children: [
                      // 极淡的轨道弧（来自星尘）
                      Positioned(
                        right: -40,
                        top: -30,
                        child: Container(
                          width: 140,
                          height: 140,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: Colors.white.withOpacity(0.06)),
                          ),
                        ),
                      ),
                      Center(
                        child: Text(
                          first,
                          style: const TextStyle(
                            fontSize: 40,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFFEDEDED),
                          ),
                        ),
                      ),
                      // 左上角编号
                      Positioned(
                        left: 8,
                        top: 7,
                        child: Text(
                          '${(widget.index + 1).toString().padLeft(2, '0')}',
                          style: const TextStyle(
                              fontSize: 8.5,
                              fontFamily: 'monospace',
                              letterSpacing: 1,
                              color: Color(0xFF6E6E6E)),
                        ),
                      ),
                      // 底部强调条
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: Container(height: 2, color: _edge),
                      ),
                    ],
                  ),
                ),
              ),
              // 信息条
              Container(
                padding: const EdgeInsets.fromLTRB(9, 8, 9, 9),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: GColors.line)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: GColors.text,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${widget.sizeKb} KB · .gal',
                      style: const TextStyle(
                          fontSize: 9,
                          fontFamily: 'monospace',
                          color: GColors.dim,
                          letterSpacing: 0.6),
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

class _EmptyShelf extends StatelessWidget {
  const _EmptyShelf();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 46),
      child: Column(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              border: Border.all(color: GColors.line),
            ),
            child: const Icon(Icons.menu_book_outlined,
                color: GColors.dim, size: 22),
          ),
          const SizedBox(height: 14),
          const Text('书架是空的',
              style: TextStyle(fontSize: 13, color: GColors.text)),
          const SizedBox(height: 6),
          const Text('新建一本，或者从「示例」开始',
              style: TextStyle(fontSize: 11, color: GColors.dim)),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ 背景

class _ShelfBackground extends StatelessWidget {
  const _ShelfBackground();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF0C0C0E), GColors.ink, Color(0xFF070708)],
            ),
          ),
        ),
        // 极淡的竖向木纹
        Positioned.fill(
          child: CustomPaint(painter: _GrainPainter()),
        ),
      ],
    );
  }
}

class _GrainPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Colors.white.withOpacity(0.022)
      ..strokeWidth = 1;
    for (var x = 0.0; x < size.width; x += 13) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
  }

  @override
  bool shouldRepaint(_GrainPainter old) => false;
}