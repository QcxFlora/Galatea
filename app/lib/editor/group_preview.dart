import 'package:flutter/material.dart';

import '../models/graph.dart';
import '../theme.dart';

/// 组合块（group）的「单个渲染预览」：把组内节点当作可拖拽元素排版，
/// 生成一个排版块（layout）连回组合块；也可手k关键帧一键生成 Rust 脚本块。
class GroupPreviewSheet extends StatefulWidget {
  final Story story;
  final Map<String, Object?> group;
  final VoidCallback onChanged;
  const GroupPreviewSheet({
    super.key,
    required this.story,
    required this.group,
    required this.onChanged,
  });

  /// 入口：先选组合块，再进预览。没有分组时明确提示（不静默）。
  static Future<void> show(
      BuildContext context, Story story, VoidCallback onChanged) async {
    if (story.groups.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('还没有组合块：先在画布框选节点建分组，再来预览排版')));
      return;
    }
    final g = await showModalBottomSheet<Map<String, Object?>>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.all(14),
              child: Text('选择要预览排版的组合块',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            ),
            for (final g in story.groups)
              ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: Text('${g['title']}'),
                subtitle: Text('${(g['nodes'] as List?)?.length ?? 0} 个节点'),
                onTap: () => Navigator.pop(ctx, g),
              ),
          ],
        ),
      ),
    );
    if (g == null || !context.mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => GroupPreviewSheet(story: story, group: g, onChanged: onChanged),
    );
  }

  @override
  State<GroupPreviewSheet> createState() => _GroupPreviewSheetState();
}

class _GroupPreviewSheetState extends State<GroupPreviewSheet> {
  final List<Map<String, Object?>> _items = [];
  final List<Map<String, Object?>> _kfs = [];

  @override
  void initState() {
    super.initState();
    final ids = (widget.group['nodes'] as List?)?.map((e) => '$e').toList() ?? <String>[];
    var i = 0;
    for (final id in ids) {
      _items.add({
        'node': id,
        'x': 16.0 + (i % 3) * 120.0,
        'y': 16.0 + (i ~/ 3) * 90.0,
        'scale': 1.0,
        'opacity': 1.0,
        'rot': 0.0,
      });
      i++;
    }
  }

  StoryNode? _node(String id) => widget.story.nodeById(id);

  void _genLayout() {
    final n = StoryNode(
      id: 'layout_${DateTime.now().millisecondsSinceEpoch}',
      type: NodeType.layoutBlock,
      x: 40,
      y: 40,
      layoutGroup: '${widget.group['id']}',
      layoutItems: _items.map((e) => Map<String, Object?>.from(e)).toList(),
      title: '排版 · ${widget.group['title']}',
    );
    widget.story.nodes.add(n);
    widget.onChanged();
    Navigator.pop(context);
  }

  void _genScript() {
    final buf = StringBuffer();
    buf.writeln('// 由组合块「${widget.group['title']}」预览手k生成');
    buf.writeln('// 每行一个关键帧补间：node|prop|from|to|start|dur');
    for (final k in _kfs) {
      buf.writeln(
          'emit("anim", "${k['node']}|${k['prop']}|${k['from']}|${k['to']}|${k['t']}|${k['dur']}");');
    }
    if (_kfs.isEmpty) buf.writeln('emit("log", "（没有关键帧）");');
    final n = StoryNode(
      id: 'kf_${DateTime.now().millisecondsSinceEpoch}',
      type: NodeType.script,
      x: 40,
      y: 140,
      scriptEngine: 'rust',
      code: buf.toString(),
      entry: 'main',
      title: '手k动画 · ${widget.group['title']}',
    );
    widget.story.nodes.add(n);
    widget.onChanged();
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (_, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.all(14),
        children: [
          Text('预览排版 · ${widget.group['title']}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          const Text('拖拽下面的元素排版；位置会写进排版块。',
              style: TextStyle(fontSize: 11, color: GColors.dim)),
          const SizedBox(height: 10),
          SizedBox(
            height: 300,
            child: LayoutBuilder(builder: (ctx, box) {
              return Container(
                decoration: BoxDecoration(
                  color: GColors.panel2,
                  borderRadius: const BorderRadius.all(Radius.circular(10)),
                  border: Border.all(color: GColors.line),
                ),
                child: Stack(
                  children: [
                    for (var i = 0; i < _items.length; i++)
                      Positioned(
                        left: (_items[i]['x'] as num).toDouble(),
                        top: (_items[i]['y'] as num).toDouble(),
                        child: GestureDetector(
                          onPanUpdate: (d) {
                            setState(() {
                              _items[i]['x'] = ((_items[i]['x'] as num) + d.delta.dx)
                                  .clamp(0.0, box.maxWidth - 100);
                              _items[i]['y'] = ((_items[i]['y'] as num) + d.delta.dy)
                                  .clamp(0.0, box.maxHeight - 40);
                            });
                          },
                          child: Container(
                            width: 100,
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: GColors.panel,
                              borderRadius:
                                  const BorderRadius.all(Radius.circular(8)),
                              border: Border.all(color: GColors.accent),
                            ),
                            child: Text(
                              _node('${_items[i]['node']}')?.displayTitle ??
                                  '${_items[i]['node']}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 10),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            }),
          ),
          const SizedBox(height: 14),
          Row(children: [
            const Text('手k关键帧',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.add, size: 18),
              onPressed: () => setState(() => _kfs.add({
                    'node': _items.isNotEmpty ? '${_items[0]['node']}' : '',
                    'prop': 'x',
                    'from': '0',
                    'to': '100',
                    't': '0',
                    'dur': '0.6',
                  })),
            ),
          ]),
          for (var i = 0; i < _kfs.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _kfs[i]['prop'] as String,
                    isDense: true,
                    decoration: const InputDecoration(labelText: '属性'),
                    items: const [
                      DropdownMenuItem(value: 'x', child: Text('x')),
                      DropdownMenuItem(value: 'y', child: Text('y')),
                      DropdownMenuItem(value: 'scale', child: Text('scale')),
                      DropdownMenuItem(value: 'opacity', child: Text('opacity')),
                      DropdownMenuItem(value: 'rot', child: Text('rot')),
                    ],
                    onChanged: (v) => setState(() => _kfs[i]['prop'] = v ?? 'x'),
                  ),
                ),
                const SizedBox(width: 6),
                for (final f in ['from', 'to', 't', 'dur'])
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: TextFormField(
                        initialValue: '${_kfs[i][f]}',
                        decoration: InputDecoration(labelText: f, isDense: true),
                        style: const TextStyle(fontSize: 11),
                        onChanged: (v) => _kfs[i][f] = v,
                      ),
                    ),
                  ),
                IconButton(
                  icon: const Icon(Icons.close, size: 16),
                  onPressed: () => setState(() => _kfs.removeAt(i)),
                ),
              ]),
            ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _genLayout,
                icon: const Icon(Icons.dashboard_customize, size: 18),
                label: const Text('生成排版块'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _genScript,
                icon: const Icon(Icons.animation, size: 18),
                label: const Text('生成 Rust 脚本块'),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          const Text('排版块连回组合块；脚本块用 emit("anim", …) 抛关键帧，播放器/3D 侧消费。',
              style: TextStyle(fontSize: 10.5, color: GColors.dim, height: 1.5)),
        ],
      ),
    );
  }
}
