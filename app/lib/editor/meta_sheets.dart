/// 角色 / 变量 / 作品信息 三个管理面板。
library;

import 'package:flutter/material.dart';

import '../models/graph.dart';
import '../theme.dart';

class CharactersSheet extends StatefulWidget {
  final Story story;
  final VoidCallback onChanged;
  const CharactersSheet({super.key, required this.story, required this.onChanged});

  @override
  State<CharactersSheet> createState() => _CharactersSheetState();
}

class _CharactersSheetState extends State<CharactersSheet> {
  final _key = TextEditingController();
  final _name = TextEditingController();

  @override
  void dispose() {
    _key.dispose();
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chars = widget.story.characters;
    return SizedBox(
      height: 460,
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(14),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('角色',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              children: [
                for (final key in chars.keys.toList())
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: GColors.panel2,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: GColors.line),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _parseColor(chars[key]?.color) ??
                                GColors.accent,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(chars[key]?.name ?? key,
                                  style: const TextStyle(fontSize: 13)),
                              Text('key: $key',
                                  style: const TextStyle(
                                      fontSize: 10.5, color: GColors.dim)),
                            ],
                          ),
                        ),
                        IconButton(
                          iconSize: 17,
                          visualDensity: VisualDensity.compact,
                          onPressed: () {
                            setState(() => chars.remove(key));
                            widget.onChanged();
                          },
                          icon: const Icon(Icons.delete_outline,
                              color: GColors.err),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _key,
                        decoration: const InputDecoration(
                            labelText: 'key（英文）', hintText: 'yuki'),
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _name,
                        decoration: const InputDecoration(
                            labelText: '显示名', hintText: '雪'),
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: () {
                        final k = _key.text.trim();
                        final n = _name.text.trim();
                        if (k.isEmpty || n.isEmpty) return;
                        setState(() {
                          chars[k] = Character(name: n, color: '#7AA2F7');
                          _key.clear();
                          _name.clear();
                        });
                        widget.onChanged();
                      },
                      icon: const Icon(Icons.add_circle, color: GColors.accent),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class VarsSheet extends StatefulWidget {
  final Story story;
  final VoidCallback onChanged;
  const VarsSheet({super.key, required this.story, required this.onChanged});

  @override
  State<VarsSheet> createState() => _VarsSheetState();
}

class _VarsSheetState extends State<VarsSheet> {
  final _name = TextEditingController();
  String _kind = 'num';

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vars = widget.story.vars;
    return SizedBox(
      height: 460,
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(14),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('变量（好感度、flag……）',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              children: [
                for (final key in vars.keys.toList())
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: GColors.panel2,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: GColors.line),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(key,
                              style: const TextStyle(fontSize: 13)),
                        ),
                        Text('${vars[key]}',
                            style: const TextStyle(
                                fontSize: 12, color: GColors.ok)),
                        IconButton(
                          iconSize: 17,
                          visualDensity: VisualDensity.compact,
                          onPressed: () {
                            setState(() => vars.remove(key));
                            widget.onChanged();
                          },
                          icon: const Icon(Icons.delete_outline,
                              color: GColors.err),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _name,
                        decoration: const InputDecoration(
                            labelText: '变量名', hintText: '好感'),
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    const SizedBox(width: 8),
                    DropdownButton<String>(
                      value: _kind,
                      dropdownColor: GColors.panel2,
                      style: const TextStyle(fontSize: 12, color: GColors.text),
                      items: const [
                        DropdownMenuItem(value: 'num', child: Text('数字 0')),
                        DropdownMenuItem(value: 'bool', child: Text('布尔 false')),
                        DropdownMenuItem(value: 'str', child: Text('文本 ""')),
                      ],
                      onChanged: (v) => setState(() => _kind = v ?? 'num'),
                    ),
                    IconButton(
                      onPressed: () {
                        final n = _name.text.trim();
                        if (n.isEmpty) return;
                        setState(() {
                          vars[n] = _kind == 'num'
                              ? 0
                              : (_kind == 'bool' ? false : '');
                          _name.clear();
                        });
                        widget.onChanged();
                      },
                      icon: const Icon(Icons.add_circle, color: GColors.accent),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class MetaSheet extends StatefulWidget {
  final Story story;
  final VoidCallback onChanged;
  const MetaSheet({super.key, required this.story, required this.onChanged});

  @override
  State<MetaSheet> createState() => _MetaSheetState();
}

class _MetaSheetState extends State<MetaSheet> {
  late final TextEditingController _title =
      TextEditingController(text: widget.story.title);
  late final TextEditingController _author =
      TextEditingController(text: widget.story.author);
  late final TextEditingController _desc =
      TextEditingController(text: widget.story.desc);

  @override
  void dispose() {
    _title.dispose();
    _author.dispose();
    _desc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 420,
      child: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          const Text('作品信息',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          TextField(
            controller: _title,
            decoration: const InputDecoration(labelText: '标题'),
            onChanged: (v) {
              widget.story.title = v;
              widget.onChanged();
            },
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _author,
            decoration: const InputDecoration(labelText: '作者'),
            onChanged: (v) {
              widget.story.author = v;
              widget.onChanged();
            },
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _desc,
            maxLines: 4,
            decoration: const InputDecoration(labelText: '简介'),
            onChanged: (v) {
              widget.story.desc = v;
              widget.onChanged();
            },
          ),
          const SizedBox(height: 14),
          Text(
            '入口节点：${widget.story.start.isEmpty ? "（未设置）" : widget.story.start}\n'
            '节点 ${widget.story.nodes.length} 个 · 台词 ${widget.story.charCount} 字',
            style: const TextStyle(fontSize: 12, color: GColors.dim),
          ),
        ],
      ),
    );
  }
}

Color? _parseColor(String? hex) {
  if (hex == null || hex.isEmpty) return null;
  var h = hex.replaceFirst('#', '');
  if (h.length == 6) h = 'FF$h';
  final v = int.tryParse(h, radix: 16);
  if (v == null) return null;
  return Color(v);
}