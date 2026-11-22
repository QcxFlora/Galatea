/// 编辑器主页面：画布 + 属性面板 + 体检 + 试玩。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../engine/lint.dart';
import '../models/graph.dart';
import '../player/player_page.dart';
import '../storage/store.dart';
import '../theme.dart';
import 'canvas.dart';
import 'inspector.dart';
import 'meta_sheets.dart';

class EditorPage extends StatefulWidget {
  final Story story;
  final File? file;

  const EditorPage({super.key, required this.story, this.file});

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  late Story story;
  String? selected;
  List<Issue> issues = const [];
  Timer? _saveTimer;
  bool _dirty = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    story = widget.story;
    _relint();
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    super.dispose();
  }

  void _relint() {
    issues = lintStory(story);
  }

  void _changed() {
    setState(() {
      _dirty = true;
      _relint();
    });
    _scheduleSave();
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 700), _save);
  }

  Future<void> _save() async {
    if (!mounted) return;
    setState(() => _saving = true);
    try {
      await ProjectStore.save(story,
          fileName: widget.file?.uri.pathSegments.last);
      if (!mounted) return;
      setState(() {
        _dirty = false;
        _saving = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _toast('保存失败：$e');
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }

  // ------------------------------------------------------------ 节点操作

  void _addNode(NodeType type) {
    final base = selected == null ? null : story.nodeById(selected);
    final id = story.freshId(nodeTypeId(type) == 'return' ? 'ret' : nodeTypeId(type));
    double x;
    double y;
    if (base != null) {
      x = base.x + 320;
      y = base.y + 40;
    } else if (story.nodes.isEmpty) {
      x = 0;
      y = 0;
    } else {
      var maxX = double.negativeInfinity;
      var minY = double.infinity;
      for (final n in story.nodes) {
        if (n.x > maxX) maxX = n.x;
        if (n.y < minY) minY = n.y;
      }
      x = maxX + 320;
      y = minY;
    }

    final node = StoryNode(id: id, type: type, x: x, y: y);
    switch (type) {
      case NodeType.say:
        node.text = '在这里写台词……';
        break;
      case NodeType.choice:
        node.prompt = '要怎么选？';
        node.options = [Choice(text: '选项一'), Choice(text: '选项二')];
        break;
      case NodeType.branch:
        node.cond = '好感 >= 1';
        break;
      case NodeType.set:
        node.effects = [Effect(target: '好感', op: EffectOp.add, expr: '1')];
        break;
      case NodeType.end:
        node.ending = 'end_${story.nodes.where((n) => n.type == NodeType.end).length + 1}';
        node.endText = '结局文字';
        break;
      default:
        break;
    }
    story.addNode(node);

    // 从选中节点长出来：自动接上一条线（思维导图式生长）
    if (base != null) {
      final ports = nodePorts(base);
      String? free;
      for (final p in ports) {
        if (base.portTarget(p) == null) {
          free = p;
          break;
        }
      }
      if (free != null && ports.isNotEmpty) {
        base.setPort(free, id);
      }
    }
    setState(() => selected = id);
    _changed();
  }

  void _deleteSelected() {
    final id = selected;
    if (id == null) return;
    final node = story.nodeById(id);
    if (node == null) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: GColors.panel,
        title: const Text('删除节点？'),
        content: Text('「${node.displayTitle}」以及指向它的所有连线都会被删掉。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              story.removeNode(id);
              setState(() => selected = null);
              _changed();
            },
            child: const Text('删除', style: TextStyle(color: GColors.err)),
          ),
        ],
      ),
    );
  }

  void _duplicateSelected() {
    final id = selected;
    if (id == null) return;
    final node = story.nodeById(id);
    if (node == null) return;
    final copy = node.copy();
    copy.id = story.freshId(nodeTypeId(node.type));
    copy.x = node.x + 40;
    copy.y = node.y + 150;
    story.addNode(copy);
    setState(() => selected = copy.id);
    _changed();
  }

  // ------------------------------------------------------------ UI

  @override
  Widget build(BuildContext context) {
    final (errors, warnings, infos) = lintSummary(issues);
    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: _rename,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(story.title,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.edit, size: 13, color: GColors.dim),
            ],
          ),
        ),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 10),
              child: SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Icon(
                _dirty ? Icons.cloud_upload_outlined : Icons.cloud_done_outlined,
                size: 18,
                color: _dirty ? GColors.warn : GColors.ok,
              ),
            ),
          IconButton(
            tooltip: '试玩',
            onPressed: _play,
            icon: const Icon(Icons.play_circle_fill, color: GColors.accent),
          ),
          IconButton(
            tooltip: '体检',
            onPressed: _showIssues,
            icon: Badge(
              isLabelVisible: errors + warnings > 0,
              label: Text('${errors + warnings}'),
              child: const Icon(Icons.fact_check_outlined),
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            color: GColors.panel2,
            onSelected: (v) {
              switch (v) {
                case 'layout':
                  story.autoLayout();
                  _changed();
                  _toast('已按思维导图重新排布');
                  break;
                case 'chars':
                  _showCharacters();
                  break;
                case 'vars':
                  _showVars();
                  break;
                case 'export':
                  _export();
                  break;
                case 'import':
                  _import();
                  break;
                case 'meta':
                  _showMeta();
                  break;
              }
            },
            itemBuilder: (ctx) => const [
              PopupMenuItem(value: 'layout', child: Text('自动布局')),
              PopupMenuItem(value: 'chars', child: Text('角色管理')),
              PopupMenuItem(value: 'vars', child: Text('变量管理')),
              PopupMenuItem(value: 'meta', child: Text('作品信息')),
              PopupMenuDivider(),
              PopupMenuItem(value: 'export', child: Text('导出 JSON')),
              PopupMenuItem(value: 'import', child: Text('从 JSON 覆盖导入')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: GraphCanvas(
              story: story,
              selectedId: selected,
              onSelect: (id) => setState(() => selected = id),
              onChanged: _changed,
              onToast: _toast,
            ),
          ),
          _issueBar(errors, warnings, infos),
          if (selected != null && story.nodeById(selected) != null)
            SizedBox(
              height: 300,
              child: Inspector(
                story: story,
                nodeId: selected!,
                onChanged: _changed,
                onClose: () => setState(() => selected = null),
                onDelete: _deleteSelected,
                onDuplicate: _duplicateSelected,
              ),
            )
          else
            _toolbar(),
        ],
      ),
    );
  }

  Widget _issueBar(int errors, int warnings, int infos) {
    final color = errors > 0
        ? GColors.err
        : (warnings > 0 ? GColors.warn : GColors.ok);
    return GestureDetector(
      onTap: _showIssues,
      child: Container(
        height: 30,
        color: GColors.panel,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            Icon(
              errors > 0
                  ? Icons.error_outline
                  : (warnings > 0
                      ? Icons.warning_amber_outlined
                      : Icons.check_circle_outline),
              size: 15,
              color: color,
            ),
            const SizedBox(width: 6),
            Text(
              errors + warnings + infos == 0
                  ? '剧本很健康 · ${story.nodes.length} 个节点 · ${story.charCount} 字'
                  : '$errors 错误 / $warnings 警告 / $infos 提示 · 点这里查看',
              style: TextStyle(fontSize: 11.5, color: color),
            ),
            const Spacer(),
            Text('${story.nodes.length} 节点',
                style: const TextStyle(fontSize: 11, color: GColors.dim)),
          ],
        ),
      ),
    );
  }

  Widget _toolbar() {
    const types = [
      NodeType.say,
      NodeType.choice,
      NodeType.branch,
      NodeType.set,
      NodeType.jump,
      NodeType.call,
      NodeType.ret,
      NodeType.end,
    ];
    return Container(
      height: 62,
      color: GColors.panel,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        children: [
          for (final t in types)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: _ToolChip(
                icon: nodeTypeIcon(t),
                label: nodeTypeLabel(t),
                color: GColors.forNodeType(nodeTypeId(t)),
                onTap: () => _addNode(t),
              ),
            ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------ 弹层

  void _play() {
    if (story.start.isEmpty || story.nodeById(story.start) == null) {
      _toast('先给某个节点点上 ★ 设为入口');
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlayerPage(story: story.copy()),
      ),
    );
  }

  void _showIssues() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: GColors.panel,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.5,
        maxChildSize: 0.9,
        builder: (_, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.all(14),
          children: [
            const Text('剧本体检',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            if (issues.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Text('没有问题，可以打包了 ✨',
                    style: TextStyle(color: GColors.ok)),
              ),
            for (final it in issues)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  it.level == IssueLevel.error
                      ? Icons.error_outline
                      : (it.level == IssueLevel.warning
                          ? Icons.warning_amber_outlined
                          : Icons.info_outline),
                  size: 18,
                  color: it.level == IssueLevel.error
                      ? GColors.err
                      : (it.level == IssueLevel.warning
                          ? GColors.warn
                          : GColors.dim),
                ),
                title: Text(it.msg, style: const TextStyle(fontSize: 13)),
                subtitle: it.node == null
                    ? null
                    : Text(it.node!,
                        style:
                            const TextStyle(fontSize: 11, color: GColors.dim)),
                onTap: it.node == null
                    ? null
                    : () {
                        Navigator.pop(ctx);
                        setState(() => selected = it.node);
                      },
              ),
          ],
        ),
      ),
    );
  }

  void _showCharacters() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: GColors.panel,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: CharactersSheet(
          story: story,
          onChanged: _changed,
        ),
      ),
    );
  }

  void _showVars() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: GColors.panel,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: VarsSheet(story: story, onChanged: _changed),
      ),
    );
  }

  void _showMeta() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: GColors.panel,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: MetaSheet(story: story, onChanged: _changed),
      ),
    );
  }

  void _rename() {
    final controller = TextEditingController(text: story.title);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: GColors.panel,
        title: const Text('作品名'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '例如：雨声与自动门'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () {
              final v = controller.text.trim();
              if (v.isNotEmpty) {
                story.title = v;
                _changed();
              }
              Navigator.pop(ctx);
            },
            child: const Text('好'),
          ),
        ],
      ),
    );
  }

  void _export() {
    final text = story.toPrettyJson();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: GColors.panel,
        title: const Text('导出剧本'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('这就是 .gala.json，Rust 打包器和播放器读的都是它。',
                  style: TextStyle(fontSize: 12, color: GColors.dim)),
              const SizedBox(height: 8),
              Flexible(
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: GColors.bg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      text,
                      style: const TextStyle(
                          fontSize: 10.5,
                          fontFamily: 'monospace',
                          color: GColors.text),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: text));
              if (ctx.mounted) Navigator.pop(ctx);
              _toast('已复制到剪贴板');
            },
            child: const Text('复制全部'),
          ),
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('关闭')),
        ],
      ),
    );
  }

  void _import() {
    final controller = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: GColors.panel,
        title: const Text('从 JSON 导入'),
        content: SizedBox(
          width: 420,
          child: TextField(
            controller: controller,
            maxLines: 10,
            style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
            decoration: const InputDecoration(
                hintText: '把 .gala.json 的内容粘进来（会覆盖当前作品）'),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () {
              try {
                final raw = jsonDecode(controller.text);
                if (raw is! Map) throw const FormatException('不是 JSON 对象');
                final decoded = Story.fromJson(Map<String, dynamic>.from(raw));
                story = decoded;
                selected = null;
                Navigator.pop(ctx);
                _changed();
                _toast('导入成功');
              } catch (e) {
                _toast('导入失败：$e');
              }
            },
            child: const Text('导入'),
          ),
        ],
      ),
    );
  }
}

class _ToolChip extends StatelessWidget {
  final String icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ToolChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.14),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.5)),
        ),
        child: Row(
          children: [
            Text(icon, style: const TextStyle(fontSize: 14)),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    fontSize: 12.5, color: color, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}