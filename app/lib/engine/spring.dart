/// lilt 式弹簧动画（Flutter 版）
///
/// 设计哲学来自 [chhongzh/lilt](https://github.com/chhongzh/lilt)：
/// **不用缓动曲线，所有会动的东西都由阻尼弹簧驱动**。
/// 参数用 SwiftUI 的写法：`response`（快慢）× `damping`（弹度，1=不过冲）。
///
/// 积分方式与 lilt 一致：半隐式欧拉 + 1/240s 子步，因此帧率变化不影响手感。
library;

import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

const double _tau = 6.283185307179586;

class SpringPreset {
  /// 无阻尼振动周期（秒）——决定快慢
  final double response;

  /// 临界阻尼比：1 = 不过冲，0.45 = 明显回弹
  final double damping;

  const SpringPreset(this.response, this.damping);

  static const SpringPreset smooth = SpringPreset(0.39, 0.85); // 页面/弹层
  static const SpringPreset snappy = SpringPreset(0.31, 0.80); // 滚动条/进度
  static const SpringPreset bouncy = SpringPreset(0.25, 0.45); // 勾选/抖动
  static const SpringPreset interactive = SpringPreset(0.14, 1.00); // 跟手
  static const SpringPreset deft = SpringPreset(0.29, 0.75); // 默认
}

/// 一个朝目标值弹过去的 double
class SpringValue {
  double value;
  double target;
  double velocity = 0;

  final SpringPreset preset;
  final double precision;

  SpringValue({
    double value = 0,
    this.preset = SpringPreset.deft,
    this.precision = 0.05,
  })  : value = value,
        target = value;

  bool get settled => value == target && velocity == 0;

  /// 弹向 t
  void set(double t) {
    target = t;
  }

  /// 立刻停在 t
  void jump(double t) {
    value = t;
    target = t;
    velocity = 0;
  }

  /// 加一个速度（px/s）
  void kick(double v) {
    velocity += v;
  }

  /// 按弹簧换算一个初速度，让值大约荡开 px 再回来
  void bump(double px) {
    kick(px * (_tau / preset.response));
  }

  /// 推进 dt 秒，返回是否仍在运动
  bool step(double dt) {
    if (settled) return false;
    final sub = (dt * 240).ceil().clamp(1, 64);
    final h = dt / sub;
    final w = _tau / preset.response;
    final k = w * w;
    final c = 2 * preset.damping * w;
    var v = velocity;
    var x = value;
    for (var i = 0; i < sub; i++) {
      final f = k * (target - x) - c * v;
      v += f * h;
      x += v * h;
    }
    value = x;
    velocity = v;
    if ((x - target).abs() < precision && v.abs() < precision * 10) {
      value = target;
      velocity = 0;
      return false;
    }
    return true;
  }
}

/// 把一个弹簧值接到 widget 树上：
///
/// ```dart
/// SpringBuilder(
///   begin: 120, target: 0, preset: SpringPreset.smooth,
///   builder: (_, v) => Transform.translate(offset: Offset(0, v), child: card),
/// )
/// ```
class SpringBuilder extends StatefulWidget {
  final double begin;
  final double target;
  final SpringPreset preset;
  final Duration delay;
  final Widget Function(BuildContext context, double value) builder;

  const SpringBuilder({
    super.key,
    required this.begin,
    required this.target,
    required this.builder,
    this.preset = SpringPreset.deft,
    this.delay = Duration.zero,
  });

  @override
  State<SpringBuilder> createState() => _SpringBuilderState();
}

class _SpringBuilderState extends State<SpringBuilder>
    with SingleTickerProviderStateMixin {
  late final SpringValue _spring;
  Ticker? _ticker;
  Duration _last = Duration.zero;
  Timer? _delayTimer;

  @override
  void initState() {
    super.initState();
    _spring = SpringValue(value: widget.begin, preset: widget.preset);
    _ticker = createTicker(_onTick);
    if (widget.delay == Duration.zero) {
      _startToTarget();
    } else {
      _delayTimer = Timer(widget.delay, () {
        if (mounted) _startToTarget();
      });
    }
  }

  void _startToTarget() {
    _spring.set(widget.target);
    _last = Duration.zero;
    _ticker?.start();
  }

  void _onTick(Duration elapsed) {
    final dt = _last == Duration.zero
        ? 1 / 60
        : ((elapsed - _last).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _last = elapsed;
    final moving = _spring.step(dt);
    if (mounted) setState(() {});
    if (!moving) {
      _ticker?.stop();
      _last = Duration.zero;
    }
  }

  @override
  void didUpdateWidget(covariant SpringBuilder old) {
    super.didUpdateWidget(old);
    if (old.target != widget.target) {
      _spring.set(widget.target);
      if (_ticker?.isActive != true) {
        _last = Duration.zero;
        _ticker?.start();
      }
    }
  }

  @override
  void dispose() {
    _delayTimer?.cancel();
    _ticker?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _spring.value);
}