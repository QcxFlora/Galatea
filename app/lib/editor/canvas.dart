/// 思维导图画布：节点可拖、端口可拉线、双指缩放、单指平移。
///
/// 坐标体系：
///   world（剧本里的 x/y） → screen = world * scale + pan
/// 所有命中检测都在 world 里做，跟缩放无关。
library;

import 'package:flutter/material.dart';

import '../models/graph.dart';
import '../theme.dart';

const double kNodeW = 248;
const double kNodeH = 116;

/// 一个节点上所有"可以拉线出去"的端口（含还没连的）
List<String> nodePorts(StoryNode n) {
  switch (n.type) {
    case NodeType.say:
    case NodeType.set:
    case NodeType.script:
      return const ['next'];
    case NodeType.branch:
      return const ['yes', 'no'];
    case NodeType.choice:
      return [for (var i = 0; i < n.options.length; i++) 'opt$i'];
    case NodeType.jump:
      return const ['to'];
    case NodeType.call:
      return const ['to', 'back'];
    case NodeType.ret:
    case NodeType.end:
      return const [];
  }
}

String portLabel(String port) {
  if (port == 'yes') return '真';
  if (port == 'no') return '假';
  if (port == 'back') return '回';
  if (port.startsWith('opt')) return '${int.parse(port.substring(3)) + 1}';
  return '→';
}

Color portColor(String port) {
  if (port == 'yes') return GColors.ok;
  if (port == 'no') return GColors.err;
  if (port == 'back') return const Color(0xFF00B8D9);
  if (port.startsWith('opt')) return GColors.accent2;
  return GColors.accent;
}

double portCenterY(int index, int count) {
  if (count <= 0) return kNodeH / 2;
  return 26 + (index + 0.5) * (kNodeH - 38) / count;
}

Offset portWorldPos(StoryNode n, int index, int count) =>
    Offset(n.x + kNodeW, n.y + portCenterY(index, count));

Offset entryWorldPos(StoryNode n) => Offset(n.x, n.y + kNodeH / 2);

class GraphCanvas extends StatefulWidget {
  final Story story;
  final String? selectedId;
  final String? playingId;
  final ValueChanged<String?> onSelect;
  final VoidCallback onChanged;
  final ValueChanged<String> onToast;

  const GraphCanvas({
    super.key,
    required this.story,
    required this.selectedId,
    required this.onSelect,
    required this.onChanged,
    required this.onToast,
    this.playingId,
  });

  @override
  State<GraphCanvas> createState() => _GraphCanvasState();
}

class _GraphCanvasState extends State<GraphCanvas> {
  final GlobalKey _boxKey = GlobalKey();
  Offset _pan = const Offset(80, 60);
  double _scale = 0.72;

  Offset _panStart = Offset.zero;
  double _scaleStart = 1;
  Offset _focalStart = Offset.zero;

  // 正在拉的线
  String? _linkNode;
  String? _linkPort;
  Offset? _linkCursor;

  // 正在拖的节点
  String? _dragNode;
  Offset _dragNodeStart = Offset.zero;
  Offset _dragPointerStart = Offset.zero;

  Offset _toLocal(Offset global) {
    final ctx = _boxKey.currentContext;
    if (ctx == null) return global;
    final box = ctx.findRenderObject();
    if (box is RenderBox) return box.globalToLocal(global);
    return global;
  }

  Offset _toWorld(Offset local) => (local - _pan) / _scale;

  StoryNode? _hitTest(Offset world) {
    // 后画的在上层，倒着找
    for (var i = widget.story.nodes.length - 1; i >= 0; i--) {
      final n = widget.story.nodes[i];
      if (world.dx >= n.x &&
          world.dx <= n.x + kNodeW &&
          world.dy >= n.y &&
          world.dy <= n.y + kNodeH) {
        return n;
      }
    }
    return null;
  }

  void _startLink(StoryNode n, String port) {
    setState(() {
      _linkNode = n.id;
      _linkPort = port;
      _linkCursor = portWorldPos(n, nodePorts(n).indexOf(port), nodePorts(n).length);
    });
  }

  void _moveLink(Offset global) {
    setState(() => _linkCursor = _toWorld(_toLocal(global)));
  }

  void _endLink(Offset global) {
    final fromId = _linkNode;
    final port = _linkPort;
    final world = _toWorld(_toLocal(global));
    setState(() {
      _linkNode = null;
      _linkPort = null;
      _linkCursor = null;
    });
    if (fromId == null || port == null) return;
    final target = _hitTest(world);
    final from = widget.story.nodeById(fromId);
    if (from == null) return;
    if (target == null) {
      // 松手在空白处：断开这条线
      if (from.portTarget(port) != null) {
        from.setPort(port, null);
        widget.onChanged();
        widget.onToast('已断开 ${portLabel(port)} 这条线');
      }
      return;
    }
    if (target.id == fromId) {
      widget.onToast('不能连到自己身上');
      return;
    }
    from.setPort(port, target.id);
    widget.onChanged();
    widget.onToast('${from.displayTitle} → ${target.displayTitle}');
  }

  void _tapPort(StoryNode n, String port) {
    if (n.portTarget(port) != null) {
      n.setPort(port, null);
      widget.onChanged();
      widget.onToast('已断开 ${portLabel(port)}');
    } else {
      widget.onToast('按住这个小圆点，拖到另一个节点上就能连线');
    }
  }

  @override
  Widget build(BuildContext context) {
    final story = widget.story;
    return GestureDetector(
      key: _boxKey,
      behavior: HitTestBehavior.opaque,
      onTap: () => widget.onSelect(null),
      onScaleStart: (d) {
        _panStart = _pan;
        _scaleStart = _scale;
        _focalStart = d.localFocalPoint;
      },
      onScaleUpdate: (d) {
        setState(() {
          final newScale = (_scaleStart * d.scale).clamp(0.2, 2.4);
          final world = (_focalStart - _panStart) / _scaleStart;
          _scale = newScale;
          _pan = d.localFocalPoint - world * newScale;
        });
      },
      child: Container(
        color: GColors.bg,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _GridPainter(pan: _pan, scale: _scale),
              ),
            ),
            Positioned.fill(
              child: CustomPaint(
                painter: _EdgePainter(
                  story: story,
                  pan: _pan,
                  scale: _scale,
                  selectedId: widget.selectedId,
                  linkFrom: _linkNode,
                  linkPort: _linkPort,
                  linkCursor: _linkCursor,
                ),
              ),
            ),
            for (final n in story.nodes)
              Positioned(
                left: n.x * _scale + _pan.dx,
                top: n.y * _scale + _pan.dy,
                child: Transform.scale(
                  scale: _scale,
                  alignment: Alignment.topLeft,
                  child: _NodeCard(
                    node: n,
                    selected: widget.selectedId == n.id,
                    playing: widget.playingId == n.id,
                    isStart: story.start == n.id,
                    onTap: () => widget.onSelect(n.id),
                    onSetStart: () {
                      story.start = n.id;
                      widget.onChanged();
                      widget.onToast('入口设为 ${n.displayTitle}');
                    },
                    onDragStart: (global) {
                      _dragNode = n.id;
                      _dragNodeStart = Offset(n.x, n.y);
                      _dragPointerStart = _toWorld(_toLocal(global));
                    },
                    onDragUpdate: (global) {
                      if (_dragNode != n.id) return;
                      final w = _toWorld(_toLocal(global));
                      setState(() {
                        n.x = _dragNodeStart.dx + (w.dx - _dragPointerStart.dx);
                        n.y = _dragNodeStart.dy + (w.dy - _dragPointerStart.dy);
                      });
                    },
                    onDragEnd: () {
                      _dragNode = null;
                      widget.onChanged();
                    },
                    onPortStart: (port) => _startLink(n, port),
                    onPortMove: _moveLink,
                    onPortEnd: _endLink,
                    onPortTap: (port) => _tapPort(n, port),
                  ),
                ),
              ),
            Positioned(
              left: 12,
              bottom: 12,
              child: _ZoomBadge(
                scale: _scale,
                onReset: () => setState(() {
                  _scale = 0.72;
                  _pan = const Offset(80, 60);
                }),
                onFit: _fitAll,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _fitAll() {
    final nodes = widget.story.nodes;
    if (nodes.isEmpty) return;
    var minX = double.infinity, minY = double.infinity;
    var maxX = double.negativeInfinity, maxY = double.negativeInfinity;
    for (final n in nodes) {
      minX = n.x < minX ? n.x : minX;
      minY = n.y < minY ? n.y : minY;
      maxX = (n.x + kNodeW) > maxX ? (n.x + kNodeW) : maxX;
      maxY = (n.y + kNodeH) > maxY ? (n.y + kNodeH) : maxY;
    }
    final ctx = _boxKey.currentContext;
    if (ctx == null) return;
    final box = ctx.findRenderObject();
    if (box is! RenderBox) return;
    final size = box.size;
    final w = (maxX - minX).clamp(1.0, double.infinity);
    final h = (maxY - minY).clamp(1.0, double.infinity);
    final s = ((size.width - 60) / w).clamp(0.2, 1.4);
    final s2 = ((size.height - 60) / h).clamp(0.2, 1.4);
    final scale = s < s2 ? s : s2;
    setState(() {
      _scale = scale;
      _pan = Offset(
        (size.width - w * scale) / 2 - minX * scale,
        (size.height - h * scale) / 2 - minY * scale,
      );
    });
  }
}

// ------------------------------------------------------------------ 节点卡片

class _NodeCard extends StatelessWidget {
  final StoryNode node;
  final bool selected;
  final bool playing;
  final bool isStart;
  final VoidCallback onTap;
  final VoidCallback onSetStart;
  final ValueChanged<Offset> onDragStart;
  final ValueChanged<Offset> onDragUpdate;
  final VoidCallback onDragEnd;
  final ValueChanged<String> onPortStart;
  final ValueChanged<Offset> onPortMove;
  final ValueChanged<Offset> onPortEnd;
  final ValueChanged<String> onPortTap;

  const _NodeCard({
    required this.node,
    required this.selected,
    required this.playing,
    required this.isStart,
    required this.onTap,
    required this.onSetStart,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onPortStart,
    required this.onPortMove,
    required this.onPortEnd,
    required this.onPortTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = GColors.forNodeType(nodeTypeId(node.type));
    final ports = nodePorts(node);
    return SizedBox(
      width: kNodeW,
      height: kNodeH,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            onPanStart: (d) => onDragStart(d.globalPosition),
            onPanUpdate: (d) => onDragUpdate(d.globalPosition),
            onPanEnd: (_) => onDragEnd(),
            child: Container(
              width: kNodeW,
              height: kNodeH,
              decoration: BoxDecoration(
                color: playing ? const Color(0xFF232C42) : GColors.panel,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: playing
                      ? GColors.warn
                      : (selected ? accent : GColors.line),
                  width: selected || playing ? 2 : 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.35),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 30,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: accent.withOpacity(0.16),
                      borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(11)),
                    ),
                    child: Row(
                      children: [
                        Text(nodeTypeIcon(node.type),
                            style: const TextStyle(fontSize: 12)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            node.displayTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: accent,
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: onSetStart,
                          behavior: HitTestBehavior.opaque,
                          child: Padding(
                            padding: const EdgeInsets.all(2),
                            child: Icon(
                              isStart ? Icons.star : Icons.star_border,
                              size: 15,
                              color: isStart ? GColors.warn : GColors.dim,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
                      child: Text(
                        node.summary.isEmpty ? '（空）' : node.summary,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          height: 1.35,
                          color: GColors.text,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          for (var i = 0; i < ports.length; i++)
            Positioned(
              right: -12,
              top: portCenterY(i, ports.length) - 12,
              child: _PortDot(
                label: portLabel(ports[i]),
                color: portColor(ports[i]),
                connected: node.portTarget(ports[i]) != null,
                onStart: () => onPortStart(ports[i]),
                onMove: onPortMove,
                onEnd: onPortEnd,
                onTap: () => onPortTap(ports[i]),
              ),
            ),
        ],
      ),
    );
  }
}

class _PortDot extends StatelessWidget {
  final String label;
  final Color color;
  final bool connected;
  final VoidCallback onStart;
  final ValueChanged<Offset> onMove;
  final ValueChanged<Offset> onEnd;
  final VoidCallback onTap;

  const _PortDot({
    required this.label,
    required this.color,
    required this.connected,
    required this.onStart,
    required this.onMove,
    required this.onEnd,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onPanStart: (_) => onStart(),
      onPanUpdate: (d) => onMove(d.globalPosition),
      onPanEnd: (d) => onEnd(d.globalPosition),
      child: SizedBox(
        width: 26,
        height: 24,
        child: Center(
          child: Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: connected ? color : GColors.panel2,
              border: Border.all(color: color, width: 2),
            ),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 9,
                  height: 1,
                  fontWeight: FontWeight.bold,
                  color: connected ? Colors.white : color,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ 绘制

class _GridPainter extends CustomPainter {
  final Offset pan;
  final double scale;
  _GridPainter({required this.pan, required this.scale});

  @override
  void paint(Canvas canvas, Size size) {
    final step = 40 * scale;
    if (step < 8) return;
    final paint = Paint()
      ..color = const Color(0xFF1A2130)
      ..strokeWidth = 1;
    final startX = pan.dx % step;
    final startY = pan.dy % step;
    for (var x = startX; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = startY; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) =>
      old.pan != pan || old.scale != scale;
}

class _EdgePainter extends CustomPainter {
  final Story story;
  final Offset pan;
  final double scale;
  final String? selectedId;
  final String? linkFrom;
  final String? linkPort;
  final Offset? linkCursor;

  _EdgePainter({
    required this.story,
    required this.pan,
    required this.scale,
    required this.selectedId,
    required this.linkFrom,
    required this.linkPort,
    required this.linkCursor,
  });

  Offset _s(Offset world) => world * scale + pan;

  @override
  void paint(Canvas canvas, Size size) {
    for (final n in story.nodes) {
      final ports = nodePorts(n);
      for (var i = 0; i < ports.length; i++) {
        final targetId = n.portTarget(ports[i]);
        if (targetId == null) continue;
        final target = story.nodeById(targetId);
        if (target == null) continue;
        final from = _s(portWorldPos(n, i, ports.length));
        final to = _s(entryWorldPos(target));
        final active = selectedId == n.id || selectedId == target.id;
        _edge(canvas, from, to, portColor(ports[i]), active);
      }
    }
    // 正在拉的线
    if (linkFrom != null && linkPort != null && linkCursor != null) {
      final n = story.nodeById(linkFrom);
      if (n != null) {
        final ports = nodePorts(n);
        final idx = ports.indexOf(linkPort!);
        final from = _s(portWorldPos(n, idx < 0 ? 0 : idx, ports.length));
        final to = _s(linkCursor!);
        final paint = Paint()
          ..color = portColor(linkPort!).withOpacity(0.9)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4;
        final path = Path()..moveTo(from.dx, from.dy);
        final dx = ((to.dx - from.dx).abs()).clamp(40.0, 180.0);
        path.cubicTo(from.dx + dx, from.dy, to.dx - dx, to.dy, to.dx, to.dy);
        canvas.drawPath(path, paint);
        canvas.drawCircle(to, 5, Paint()..color = portColor(linkPort!));
      }
    }
  }

  void _edge(Canvas canvas, Offset from, Offset to, Color color, bool active) {
    final paint = Paint()
      ..color = color.withOpacity(active ? 1.0 : 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = active ? 3.0 : 2.0
      ..strokeCap = StrokeCap.round;
    final path = Path()..moveTo(from.dx, from.dy);
    final dx = ((to.dx - from.dx).abs()).clamp(48.0, 200.0);
    path.cubicTo(from.dx + dx, from.dy, to.dx - dx, to.dy, to.dx, to.dy);
    canvas.drawPath(path, paint);
    // 箭头
    final arrow = Paint()..color = color.withOpacity(active ? 1.0 : 0.7);
    final p = Path()
      ..moveTo(to.dx, to.dy)
      ..lineTo(to.dx - 9, to.dy - 5)
      ..lineTo(to.dx - 9, to.dy + 5)
      ..close();
    canvas.drawPath(p, arrow);
  }

  @override
  bool shouldRepaint(_EdgePainter old) => true;
}

class _ZoomBadge extends StatelessWidget {
  final double scale;
  final VoidCallback onReset;
  final VoidCallback onFit;

  const _ZoomBadge({
    required this.scale,
    required this.onReset,
    required this.onFit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: GColors.panel.withOpacity(0.9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: GColors.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            iconSize: 18,
            onPressed: onFit,
            icon: const Icon(Icons.fit_screen, color: GColors.dim),
            tooltip: '全览',
          ),
          Text('${(scale * 100).round()}%',
              style: const TextStyle(fontSize: 11, color: GColors.dim)),
          IconButton(
            visualDensity: VisualDensity.compact,
            iconSize: 18,
            onPressed: onReset,
            icon: const Icon(Icons.center_focus_strong, color: GColors.dim),
            tooltip: '复位',
          ),
        ],
      ),
    );
  }
}