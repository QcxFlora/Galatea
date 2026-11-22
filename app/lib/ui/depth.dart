/// 3D 分层悬空（扁平 2.5D）。
///
/// 《来自星尘》的界面不是贴平的：卡片浮在空中，背景退得很远，
/// 手指一动，各层以不同速度错开，卡片还会朝你倾斜一点点。
///
/// Flutter 里没有真 3D 场景，但用 `Matrix4` 的 perspective + rotate + translate
/// 就足够做出"薄片悬空"的观感——关键是三件事：
///   1. **透视**：`setEntry(3, 2, 0.0015)`，离得近的变大
///   2. **分层**：每层给不同的 z，视差就出来了
///   3. **弹簧**：倾斜和抬升都由 [SpringBuilder] 驱动，不做硬切
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../engine/spring.dart';
import '../theme.dart';

/// 把一整个界面放进有透视的空间里，指针移动时各层错开。
class DepthScene extends StatefulWidget {
  final Widget child;
  /// 倾斜上限（度）
  final double maxTilt;
  /// 是否需要按压回弹
  final bool enablePointer;

  const DepthScene({
    super.key,
    required this.child,
    this.maxTilt = 3.0,
    this.enablePointer = true,
  });

  @override
  State<DepthScene> createState() => _DepthSceneState();
}

class _DepthSceneState extends State<DepthScene> {
  final SpringValue _rx = SpringValue(preset: SpringPreset.smooth, precision: 0.02);
  final SpringValue _ry = SpringValue(preset: SpringPreset.smooth, precision: 0.02);

  void _onMove(Offset local, Size size) {
    if (!widget.enablePointer) return;
    final nx = (local.dx / size.width - 0.5) * 2; // -1..1
    final ny = (local.dy / size.height - 0.5) * 2;
    _ry.set(nx * widget.maxTilt);
    _rx.set(-ny * widget.maxTilt);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final size = Size(box.maxWidth, box.maxHeight);
      return MouseRegion(
        onHover: (e) => _onMove(e.localPosition, size),
        child: Listener(
          onPointerMove: (e) => _onMove(e.localPosition, size),
          onPointerUp: (_) {
            _rx.set(0);
            _ry.set(0);
          },
          onPointerCancel: (_) {
            _rx.set(0);
            _ry.set(0);
          },
          child: _Animated444(_rx, _ry, child: widget.child),
        ),
      );
    });
  }
}

/// 一个内部小组件，把两个弹簧值应用到 Matrix4
class _Animated444 extends StatelessWidget {
  final SpringValue rx;
  final SpringValue ry;
  final Widget child;

  const _Animated444(this.rx, this.ry, {required this.child});

  @override
  Widget build(BuildContext context) {
    return _SpringRect(
      springs: [rx, ry],
      builder: (_, values) {
        final m = Matrix4.identity()
          ..setEntry(3, 2, 0.0012)
          ..rotateX(values[0] * math.pi / 180)
          ..rotateY(values[1] * math.pi / 180);
        return Transform(alignment: Alignment.center, transform: m, child: child);
      },
    );
  }
}

/// 监听若干 SpringValue，每帧重建
class _SpringRect extends StatefulWidget {
  final List<SpringValue> springs;
  final Widget Function(BuildContext, List<double>) builder;

  const _SpringRect({required this.springs, required this.builder});

  @override
  State<_SpringRect> createState() => _SpringRectState();
}

class _SpringRectState extends State<_SpringRect>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
  }

  void _onTick(Duration elapsed) {
    final dt = _last == Duration.zero
        ? 1 / 60
        : ((elapsed - _last).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _last = elapsed;
    var moving = false;
    for (final s in widget.springs) {
      if (s.step(dt)) moving = true;
    }
    if (mounted) setState(() {});
    if (!moving) {
      _ticker.stop();
      _last = Duration.zero;
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, widget.springs.map((s) => s.value).toList());
}

/// 悬空的卡片：按下会抬起来，还会朝手指方向倾斜。
class DepthCard extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  /// 基础悬空高度（决定阴影与透视缩放）
  final double elevation;
  /// 是否允许倾斜
  final bool tilt;

  const DepthCard({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.elevation = 8,
    this.tilt = true,
  });

  @override
  State<DepthCard> createState() => _DepthCardState();
}

class _DepthCardState extends State<DepthCard>
    with SingleTickerProviderStateMixin {
  late final SpringValue _lift;
  late final SpringValue _rx;
  late final SpringValue _ry;
  late final Ticker _ticker;
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    _lift = SpringValue(preset: SpringPreset.snappy, precision: 0.002);
    _rx = SpringValue(preset: SpringPreset.bouncy, precision: 0.05);
    _ry = SpringValue(preset: SpringPreset.bouncy, precision: 0.05);
    _ticker = createTicker(_onTick)..start();
  }

  void _onTick(Duration elapsed) {
    final dt = _last == Duration.zero
        ? 1 / 60
        : ((elapsed - _last).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _last = elapsed;
    var moving = false;
    for (final s in [_lift, _rx, _ry]) {
      if (s.step(dt)) moving = true;
    }
    if (mounted) setState(() {});
    if (!moving) {
      _ticker.stop();
      _last = Duration.zero;
    }
  }

  void _wake() {
    if (_ticker.isActive) return;
    _last = Duration.zero;
    _ticker.start();
  }

  void _down(Offset local, Size size) {
    _lift.set(1);
    if (widget.tilt && size.width > 0) {
      final nx = (local.dx / size.width - 0.5) * 2;
      final ny = (local.dy / size.height - 0.5) * 2;
      _rx.set(-ny * 4);
      _ry.set(nx * 4);
    }
    _wake();
  }

  void _up() {
    _lift.set(0);
    _rx.set(0);
    _ry.set(0);
    _wake();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final size = Size(box.maxWidth, box.maxHeight);
      return GestureDetector(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        onTapDown: (d) => _down(d.localPosition, size),
        onTapUp: (_) => _up(),
        onTapCancel: _up,
        child: Builder(builder: (_) {
          final lift = _lift.value;
          final scale = 1 + lift * 0.012;
          final m = Matrix4.identity()
            ..setEntry(3, 2, 0.0016)
            ..rotateX(_rx.value * math.pi / 180)
            ..rotateY(_ry.value * math.pi / 180)
            ..translate(0.0, 0.0, lift * widget.elevation);
          return Transform(
            alignment: Alignment.center,
            transform: m,
            child: Transform.scale(
              scale: scale,
              child: _ShadowWrap(
                lift: lift,
                elevation: widget.elevation,
                child: widget.child,
              ),
            ),
          );
        }),
      );
    });
  }
}

/// 阴影随悬空高度变化（浮得越高，影子越大越淡）
class _ShadowWrap extends StatelessWidget {
  final double lift;
  final double elevation;
  final Widget child;

  const _ShadowWrap({
    required this.lift,
    required this.elevation,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final blur = 14 + lift * 16;
    final dy = 4 + lift * 10;
    final alpha = 0.10 + lift * 0.06;
    return Container(
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.all(Radius.circular(14)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(alpha),
            blurRadius: blur,
            offset: Offset(0, dy),
          ),
        ],
      ),
      child: child,
    );
  }
}

/// 远景层：比内容层退后，指针移动时反向偏移
class DepthBackdrop extends StatelessWidget {
  final Widget child;
  final double depth;

  const DepthBackdrop({super.key, required this.child, this.depth = 0.4});

  @override
  Widget build(BuildContext context) {
    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()
        ..setEntry(3, 2, 0.0012)
        ..translate(0.0, 0.0, -60.0 * depth),
      child: Opacity(opacity: 0.9, child: child),
    );
  }
}

/// 一层细的"漂浮装饰线"，用来给场景加深度线索
class DepthRails extends StatelessWidget {
  final double depth;
  const DepthRails({super.key, this.depth = 0.6});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _RailPainter(depth),
        size: Size.infinite,
      ),
    );
  }
}

class _RailPainter extends CustomPainter {
  final double depth;
  _RailPainter(this.depth);

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = GColors.accent.withOpacity(0.10)
      ..strokeWidth = 1;

    // 三道斜线，模拟"脚手架/轨道"层
    for (var i = 0; i < 3; i++) {
      final y0 = size.height * (0.18 + i * 0.28);
      final path = Path()
        ..moveTo(-40, y0 + 26 * depth)
        ..lineTo(size.width * 0.42, y0 - 10 * depth);
      canvas.drawPath(path, p);
    }
    // 右侧一个极淡的圆
    canvas.drawCircle(
      Offset(size.width * 0.86, size.height * 0.22),
      54,
      Paint()
        ..color = GColors.accent.withOpacity(0.07)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_RailPainter old) => old.depth != depth;
}